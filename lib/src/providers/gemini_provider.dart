import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'agent_provider.dart';
import 'provider_event.dart';
import 'sse_utils.dart';

/// Streams `generateContent` responses from Google's
/// [Gemini API](https://ai.google.dev).
///
/// Gemini's wire format genuinely differs from OpenAI-compatible APIs (see
/// `OpenRouterProvider`): the API key is a query parameter rather than an
/// `Authorization` header, roles are `user`/`model` rather than
/// `user`/`assistant`, and system instructions are a separate top-level
/// field rather than a message with role `system`.
class GeminiProvider extends AgentProvider {
  /// Your Gemini API key.
  final String apiKey;

  /// Model id, e.g. `gemini-1.5-pro` or `gemini-2.0-flash`.
  final String model;

  /// Raw Gemini-shaped function-declaration schemas, passed through as
  /// `tools: [{functionDeclarations: ...}]`. `null` omits the field.
  final List<Map<String, Object?>>? functionDeclarations;

  /// Extra body fields merged in, e.g. `{'generationConfig': {...}}`.
  final Map<String, Object?>? extraParams;

  final Uri? _endpointOverride;
  final http.Client _httpClient;
  final bool _ownsClient;

  /// Creates a Gemini provider.
  ///
  /// Pass [httpClient] to reuse an existing client (its lifecycle is then the
  /// caller's responsibility); otherwise one is created and closed by
  /// [dispose]. [endpoint] overrides the default
  /// `streamGenerateContent` URL, useful for a proxy in front of Gemini.
  GeminiProvider({
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
    Uri? endpoint,
    this.functionDeclarations,
    this.extraParams,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _endpointOverride = endpoint;

  Uri get _endpoint =>
      _endpointOverride ??
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent',
      ).replace(queryParameters: {'alt': 'sse', 'key': apiKey});

  @override
  Stream<ProviderEvent> streamEvents(List<ChatMessage> conversation) async* {
    final systemText = conversation
        .where((m) => m.role == ChatRole.system)
        .map((m) => m.text)
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    final request = http.Request('POST', _endpoint)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        if (systemText.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': systemText},
            ],
          },
        'contents': _toGeminiContents(conversation),
        if (functionDeclarations != null)
          'tools': [
            {'functionDeclarations': functionDeclarations},
          ],
        ...?extraParams,
      });

    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw AgentProviderException(response.statusCode, body);
    }

    var callCounter = 0;

    // No [DONE] sentinel here, unlike OpenRouter -- the SSE stream simply
    // ends when the HTTP response completes, and sseDataEvents' async*
    // terminates naturally at that point.
    await for (final payload in sseDataEvents(response.stream)) {
      if (payload.isEmpty) continue;

      final Map<String, Object?> json;
      try {
        json = jsonDecode(payload) as Map<String, Object?>;
      } on FormatException {
        continue;
      }

      final candidates = json['candidates'] as List<Object?>?;
      if (candidates == null || candidates.isEmpty) continue;
      final content =
          (candidates.first as Map<String, Object?>)['content']
              as Map<String, Object?>?;
      final parts = content?['parts'] as List<Object?>?;
      if (parts == null) continue;

      for (final rawPart in parts) {
        final part = rawPart as Map<String, Object?>;
        final text = part['text'] as String?;
        if (text != null && text.isNotEmpty) {
          yield TextDelta(text);
        }

        final functionCall = part['functionCall'] as Map<String, Object?>?;
        if (functionCall != null) {
          final name = functionCall['name'] as String?;
          if (name == null) continue;
          final args = functionCall['args'];
          final input = args == null
              ? '{}'
              : const JsonEncoder.withIndent('  ').convert(args);
          callCounter++;
          yield ToolCallEvent(
            ToolCall(
              // Gemini's functionCall carries no id -- synthesize one, the
              // same no-uuid-dependency approach ChatMessage's own id
              // generator uses.
              id: '${DateTime.now().microsecondsSinceEpoch}-fc-$callCounter',
              name: name,
              status: ToolCallStatus.pending,
              input: input,
            ),
          );
        }
      }
    }
  }

  List<Map<String, Object?>> _toGeminiContents(
    List<ChatMessage> conversation,
  ) {
    final contents = <Map<String, Object?>>[];
    for (final message in conversation) {
      switch (message.role) {
        case ChatRole.system:
          // Pulled into systemInstruction above, not a content turn.
          break;
        case ChatRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': message.text},
            ],
          });
        case ChatRole.assistant:
          if (message.toolCalls.isEmpty) {
            contents.add({
              'role': 'model',
              'parts': [
                {'text': message.text},
              ],
            });
            break;
          }
          contents.add({
            'role': 'model',
            'parts': [
              if (message.text.isNotEmpty) {'text': message.text},
              for (final call in message.toolCalls)
                {
                  'functionCall': {
                    'name': call.name,
                    'args': call.input == null || call.input!.isEmpty
                        ? <String, Object?>{}
                        : jsonDecode(call.input!),
                  },
                },
            ],
          });
          final finished = message.toolCalls.where((c) => c.isFinished);
          if (finished.isNotEmpty) {
            contents.add({
              'role': 'user',
              'parts': [
                for (final call in finished)
                  {
                    'functionResponse': {
                      'name': call.name,
                      'response': {
                        'content': call.output ?? call.error ?? '',
                      },
                    },
                  },
              ],
            });
          }
      }
    }
    return contents;
  }

  @override
  void dispose() {
    if (_ownsClient) _httpClient.close();
  }
}
