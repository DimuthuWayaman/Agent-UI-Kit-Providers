import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attachment.dart';
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

      // A payload that parses as valid JSON but has an unexpected shape
      // (e.g. `choices` isn't a List) throws a TypeError from the casts
      // below -- treat it the same as a FormatException: skip the one bad
      // chunk rather than failing the whole turn and losing everything
      // accumulated so far (including `pendingCalls`).
      try {
        // Checked with `is` rather than `as` so a malformed `error` field
        // can't itself throw a TypeError that gets swallowed by the catch
        // below -- a real mid-stream error must always surface.
        final error = json['error'];
        if (error is Map<String, Object?>) {
          final code = error['code'];
          throw AgentProviderException(
            code is int ? code : response.statusCode,
            error['message']?.toString() ?? jsonEncode(error),
          );
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
            final pending =
                pendingCalls.putIfAbsent(index, _PendingToolCall.new);
            final id = entry['id'] as String?;
            if (id != null) pending.id = id;
            final name = function?['name'] as String?;
            if (name != null) pending.name = name;
            final argsChunk = function?['arguments'] as String?;
            if (argsChunk != null) pending.arguments.write(argsChunk);
          }
        }
      } on TypeError {
        continue;
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
          // Only image attachments are forwarded, as OpenAI-style
          // `image_url` content parts. Documents/audio/video are model- and
          // API-dependent enough that full support is out of scope here;
          // other kinds are described in the UI but not sent to the model.
          final imageParts = <Map<String, Object?>>[];
          for (final attachment in message.attachments) {
            if (attachment.kind != AttachmentKind.image) continue;
            final url = _openAiImageUrl(attachment);
            if (url == null) continue;
            imageParts.add({
              'type': 'image_url',
              'image_url': {'url': url},
            });
          }
          messages.add({
            'role': 'user',
            // The plain-string form is used whenever there are no images;
            // the array-of-blocks form is only needed to interleave image
            // parts, and a text block within it is omitted entirely when
            // empty (an image sent with no caption) -- some backends behind
            // OpenRouter (Anthropic in particular) reject an empty text
            // content block outright.
            'content': imageParts.isEmpty
                ? message.text
                : [
                    if (message.text.isNotEmpty)
                      {'type': 'text', 'text': message.text},
                    ...imageParts,
                  ],
          });
        case ChatRole.system:
          messages.add({'role': 'system', 'content': message.text});
        case ChatRole.assistant:
          // Only finished tool calls are represented in history -- a call
          // still `pending`/`running` has no matching tool-result message
          // yet, and OpenAI-compatible APIs reject a tool_calls entry left
          // unanswered by a later turn. The call itself is still visible in
          // the UI via ChatMessage.toolCalls; it just isn't part of the API
          // history until it resolves.
          final finished = message.toolCalls.where((c) => c.isFinished).toList();
          if (finished.isEmpty) {
            // No tool calls at all, or none finished yet -- send the plain
            // text turn either way, even when [message.text] is empty: a
            // genuinely-completed empty turn must still appear in history
            // (e.g. so it isn't silently dropped from a conversation that
            // otherwise requires strict role alternation -- see
            // AgentProvider.asResponder's doc comment).
            messages.add({'role': 'assistant', 'content': message.text});
            break;
          }
          messages.add({
            'role': 'assistant',
            'content': message.text,
            'tool_calls': [
              for (final call in finished)
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
          for (final call in finished) {
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

  /// Returns a `data:` URI for in-memory [Attachment.bytes], the raw
  /// [Attachment.url] when there are no bytes, or `null` when neither is set.
  static String? _openAiImageUrl(Attachment attachment) {
    final bytes = attachment.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final mime = attachment.mimeType ?? 'application/octet-stream';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
    return attachment.url;
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
