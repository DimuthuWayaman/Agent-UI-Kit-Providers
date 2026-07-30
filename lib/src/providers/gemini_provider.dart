import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attachment.dart';
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

  Uri get _endpoint {
    final base = _endpointOverride ??
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent',
        );
    // `alt=sse` is required for streaming to work at all, so it's merged in
    // unconditionally even when [endpoint] overrides the base URL. `key` is
    // only filled in when the override doesn't already carry one, so a proxy
    // that injects its own key can omit it from the override entirely.
    final params = Map<String, String>.from(base.queryParameters)
      ..['alt'] = 'sse'
      ..putIfAbsent('key', () => apiKey);
    return base.replace(queryParameters: params);
  }

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

      // A payload that parses as valid JSON but has an unexpected shape
      // (e.g. a proxy sends `candidates` as something other than a List)
      // throws a TypeError from the casts below. Treat it the same as a
      // FormatException -- skip the one bad chunk rather than failing the
      // whole turn and losing everything accumulated so far.
      try {
        // Checked with `is` rather than `as` so a malformed `error` field
        // (e.g. not a Map) can't itself throw a TypeError that gets
        // swallowed by the catch below -- a real error must always surface.
        final error = json['error'];
        if (error is Map<String, Object?>) {
          final code = error['code'];
          throw AgentProviderException(
            code is int ? code : response.statusCode,
            error['message']?.toString() ?? jsonEncode(error),
          );
        }

        final candidates = json['candidates'] as List<Object?>?;
        if (candidates == null || candidates.isEmpty) continue;
        final candidate = candidates.first as Map<String, Object?>;
        final content = candidate['content'] as Map<String, Object?>?;
        final parts = content?['parts'] as List<Object?>?;
        if (parts == null || parts.isEmpty) {
          // No content parts and a non-STOP finish reason means the model
          // didn't actually produce (or finish) a response -- most commonly
          // a safety block. Surfacing this as a failure beats silently
          // completing the turn with nothing in it. Gemini represents "no
          // content" as either an absent `parts` field or an empty list, so
          // both are treated the same way here.
          final finishReason = candidate['finishReason'] as String?;
          if (finishReason != null && finishReason != 'STOP') {
            throw AgentProviderException(
              response.statusCode,
              'Gemini stopped generating: $finishReason',
            );
          }
          continue;
        }

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
      } on TypeError {
        continue;
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
          // Text is only included when non-empty -- an image-only message
          // (no caption) would otherwise send a blank text part, which some
          // backends behind Gemini-compatible proxies reject outright.
          final parts = <Map<String, Object?>>[
            if (message.text.isNotEmpty) {'text': message.text},
          ];
          // Only image attachments are forwarded, via Gemini's inlineData
          // (in-memory bytes) or fileData (already-hosted url) parts.
          // Documents/audio/video are model- and API-dependent enough that
          // full support is out of scope here; other kinds are described in
          // the UI but not sent to the model.
          for (final attachment in message.attachments) {
            if (attachment.kind != AttachmentKind.image) continue;
            final part = _geminiImagePart(attachment);
            if (part != null) parts.add(part);
          }
          // A turn must never end up with zero parts -- fall back to an
          // explicit empty text part so this user turn still appears in
          // history rather than silently vanishing (Gemini requires strict
          // user/model role alternation).
          if (parts.isEmpty) parts.add({'text': message.text});
          contents.add({'role': 'user', 'parts': parts});
        case ChatRole.assistant:
          // Only finished tool calls are represented in history -- a call
          // still `pending`/`running` has no matching functionResponse yet,
          // and Gemini (like OpenAI-compatible APIs) rejects a functionCall
          // left unanswered by a later turn. The call itself is still
          // visible in the UI via ChatMessage.toolCalls; it just isn't part
          // of the API history until it resolves.
          final finished = message.toolCalls.where((c) => c.isFinished).toList();
          if (finished.isEmpty) {
            // No tool calls at all, or none finished yet -- send the plain
            // text turn either way, even when [message.text] is empty: a
            // genuinely-completed empty turn must still appear in history so
            // strict role alternation isn't broken by silently dropping it
            // (see AgentProvider.asResponder's doc comment).
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
              for (final call in finished)
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
    return contents;
  }

  /// Builds a Gemini `inlineData`/`fileData` part for an image [attachment],
  /// or `null` when it carries neither in-memory bytes nor a url.
  static Map<String, Object?>? _geminiImagePart(Attachment attachment) {
    final bytes = attachment.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return {
        'inlineData': {
          'mimeType': attachment.mimeType ?? 'application/octet-stream',
          'data': base64Encode(bytes),
        },
      };
    }
    final url = attachment.url;
    if (url != null) {
      return {
        'fileData': {
          'mimeType': attachment.mimeType ?? 'application/octet-stream',
          'fileUri': url,
        },
      };
    }
    return null;
  }

  @override
  void dispose() {
    if (_ownsClient) _httpClient.close();
  }
}
