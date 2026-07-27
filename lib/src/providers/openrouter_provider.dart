import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'agent_provider.dart';
import 'provider_event.dart';
import 'sse_utils.dart';

/// Streams chat completions from [OpenRouter](https://openrouter.ai), whose
/// API mirrors OpenAI's `/chat/completions` schema and proxies models from
/// Anthropic, OpenAI, Google, Meta and others behind one key.
class OpenRouterProvider extends AgentProvider {
  /// Your OpenRouter API key.
  final String apiKey;

  /// Model id, e.g. `anthropic/claude-sonnet-4.5` or `openai/gpt-4o`.
  final String model;

  /// Raw OpenAI-shaped function/tool schemas, passed through as `tools` in
  /// the request body. `null` omits the field.
  final List<Map<String, Object?>>? tools;

  /// Extra body fields merged in, e.g. `{'temperature': 0.7}`.
  final Map<String, Object?>? extraParams;

  final Uri _endpoint;
  final http.Client _httpClient;
  final bool _ownsClient;

  /// Creates an OpenRouter provider.
  ///
  /// Pass [httpClient] to reuse an existing client (its lifecycle is then the
  /// caller's responsibility); otherwise one is created and closed by
  /// [dispose]. [endpoint] overrides the default completions URL, useful for
  /// a proxy in front of OpenRouter.
  OpenRouterProvider({
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
    Uri? endpoint,
    this.tools,
    this.extraParams,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _endpoint =
            endpoint ?? Uri.parse('https://openrouter.ai/api/v1/chat/completions');

  @override
  Stream<ProviderEvent> streamEvents(List<ChatMessage> conversation) async* {
    final request = http.Request('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': _toOpenAiMessages(conversation),
        if (tools != null) 'tools': tools,
        ...?extraParams,
      });

    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw AgentProviderException(response.statusCode, body);
    }

    final pendingCalls = <int, _PendingToolCall>{};

    await for (final payload in sseDataEvents(response.stream)) {
      if (payload == '[DONE]') break;
      if (payload.isEmpty) continue;

      final Map<String, Object?> json;
      try {
        json = jsonDecode(payload) as Map<String, Object?>;
      } on FormatException {
        // OpenRouter occasionally sends non-JSON keep-alive comments; skip
        // rather than aborting the whole stream.
        continue;
      }

      final choices = json['choices'] as List<Object?>?;
      final delta = choices == null || choices.isEmpty
          ? null
          : (choices.first as Map<String, Object?>)['delta']
              as Map<String, Object?>?;
      if (delta == null) continue;

      final content = delta['content'] as String?;
      if (content != null && content.isNotEmpty) {
        yield TextDelta(content);
      }

      final toolCalls = delta['tool_calls'] as List<Object?>?;
      if (toolCalls != null) {
        for (final raw in toolCalls) {
          final entry = raw as Map<String, Object?>;
          final index = entry['index'] as int? ?? 0;
          final function = entry['function'] as Map<String, Object?>?;
          final pending = pendingCalls.putIfAbsent(index, _PendingToolCall.new);
          final id = entry['id'] as String?;
          if (id != null) pending.id = id;
          final name = function?['name'] as String?;
          if (name != null) pending.name = name;
          final argsChunk = function?['arguments'] as String?;
          if (argsChunk != null) pending.arguments.write(argsChunk);
        }
      }
    }

    for (final pending in pendingCalls.values) {
      final call = pending.toToolCall();
      if (call != null) yield ToolCallEvent(call);
    }
  }

  List<Map<String, Object?>> _toOpenAiMessages(List<ChatMessage> conversation) {
    final messages = <Map<String, Object?>>[];
    for (final message in conversation) {
      switch (message.role) {
        case ChatRole.user:
          messages.add({'role': 'user', 'content': message.text});
        case ChatRole.system:
          messages.add({'role': 'system', 'content': message.text});
        case ChatRole.assistant:
          if (message.toolCalls.isEmpty) {
            messages.add({'role': 'assistant', 'content': message.text});
            break;
          }
          messages.add({
            'role': 'assistant',
            'content': message.text,
            'tool_calls': [
              for (final call in message.toolCalls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': call.input ?? '{}',
                  },
                },
            ],
          });
          for (final call in message.toolCalls) {
            if (!call.isFinished) continue;
            messages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': call.output ?? call.error ?? '',
            });
          }
      }
    }
    return messages;
  }

  @override
  void dispose() {
    if (_ownsClient) _httpClient.close();
  }
}

class _PendingToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  ToolCall? toToolCall() {
    final id = this.id;
    final name = this.name;
    if (id == null || name == null) return null;

    final raw = arguments.toString();
    String input;
    try {
      final parsed = jsonDecode(raw);
      input = const JsonEncoder.withIndent('  ').convert(parsed);
    } on FormatException {
      input = raw;
    }
    return ToolCall(
      id: id,
      name: name,
      status: ToolCallStatus.pending,
      input: input,
    );
  }
}
