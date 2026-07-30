import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _dataLine(Object json) => 'data: ${jsonEncode(json)}\n\n';

http.StreamedResponse _sseResponse(List<String> chunks) {
  return http.StreamedResponse(
    Stream.fromIterable(chunks.map(utf8.encode)),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

void main() {
  group('GeminiProvider', () {
    test('sends the API key as a query parameter and maps roles/system '
        'instructions/finished tool calls', () async {
      http.BaseRequest? captured;
      String? capturedBody;

      final client = MockClient.streaming((request, bodyStream) async {
        captured = request;
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });

      final provider = GeminiProvider(
        apiKey: 'gk-test',
        model: 'gemini-1.5-pro',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final conversation = [
        ChatMessage.system('be terse'),
        ChatMessage.user('what is the weather?'),
        ChatMessage.assistant(
          '',
          toolCalls: [
            const ToolCall(
              id: 'ignored-by-wire-format',
              name: 'get_weather',
              status: ToolCallStatus.success,
              input: '{"city":"Colombo"}',
              output: '29C, cloudy',
            ),
          ],
        ),
      ];

      await provider.streamEvents(conversation).toList();

      expect(captured!.url.host, 'generativelanguage.googleapis.com');
      expect(captured!.url.queryParameters['key'], 'gk-test');
      expect(captured!.url.queryParameters['alt'], 'sse');
      expect(captured!.headers.containsKey('Authorization'), isFalse);

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'be terse'},
        ],
      });

      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(3));
      expect(contents[0], {
        'role': 'user',
        'parts': [
          {'text': 'what is the weather?'},
        ],
      });
      final modelTurn = contents[1] as Map<String, Object?>;
      expect(modelTurn['role'], 'model');
      final parts = modelTurn['parts'] as List<Object?>;
      expect(
        (parts.single as Map<String, Object?>)['functionCall'],
        {
          'name': 'get_weather',
          'args': {'city': 'Colombo'},
        },
      );
      expect(contents[2], {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'name': 'get_weather',
              'response': {'content': '29C, cloudy'},
            },
          },
        ],
      });
    });

    test('streams text deltas from candidates[0].content.parts', () async {
      final sse = [
        _dataLine({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Hello'},
                ],
              },
            },
          ],
        }),
        _dataLine({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': ', world'},
                ],
              },
            },
          ],
        }),
      ].join();

      final client = MockClient.streaming((request, bodyStream) async {
        // Split mid-payload to prove chunk-boundary independence.
        final mid = sse.length ~/ 2;
        return _sseResponse([sse.substring(0, mid), sse.substring(mid)]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final events =
          await provider.streamEvents([ChatMessage.user('hi')]).toList();
      expect(events, [const TextDelta('Hello'), const TextDelta(', world')]);
    });

    test('emits a ToolCallEvent for a functionCall part, with a synthesized '
        'id since Gemini does not send one', () async {
      final sse = _dataLine({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': 'get_weather',
                    'args': {'city': 'Colombo'},
                  },
                },
              ],
            },
          },
        ],
      });
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final events =
          await provider.streamEvents([ChatMessage.user('hi')]).toList();
      expect(events, hasLength(1));
      final event = events.single as ToolCallEvent;
      expect(event.call.name, 'get_weather');
      expect(event.call.id, isNotEmpty);
      expect(event.call.status, ToolCallStatus.pending);
      expect(jsonDecode(event.call.input!), {'city': 'Colombo'});
    });

    test('endpoint override still gets alt=sse and key merged in', () async {
      http.BaseRequest? captured;
      final client = MockClient.streaming((request, bodyStream) async {
        captured = request;
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'gk-test',
        model: 'gemini-1.5-flash',
        httpClient: client,
        endpoint: Uri.parse('https://proxy.example.com/generate'),
      );
      addTearDown(provider.dispose);

      await provider.streamEvents([ChatMessage.user('hi')]).toList();

      expect(captured!.url.host, 'proxy.example.com');
      expect(captured!.url.queryParameters['alt'], 'sse');
      expect(captured!.url.queryParameters['key'], 'gk-test');
    });

    test(
      "endpoint override's own key query param is not overwritten",
      () async {
        http.BaseRequest? captured;
        final client = MockClient.streaming((request, bodyStream) async {
          captured = request;
          return _sseResponse(['']);
        });
        final provider = GeminiProvider(
          apiKey: 'gk-test',
          model: 'gemini-1.5-flash',
          httpClient: client,
          endpoint: Uri.parse(
            'https://proxy.example.com/generate?key=proxy-key',
          ),
        );
        addTearDown(provider.dispose);

        await provider.streamEvents([ChatMessage.user('hi')]).toList();

        expect(captured!.url.queryParameters['key'], 'proxy-key');
        expect(captured!.url.queryParameters['alt'], 'sse');
      },
    );

    test('a safety-blocked candidate with no content fails the turn',
        () async {
      final sse = _dataLine({
        'candidates': [
          {'finishReason': 'SAFETY'},
        ],
      });
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.streamEvents([ChatMessage.user('hi')]).toList(),
        throwsA(isA<AgentProviderException>()),
      );
    });

    test('a mid-stream error frame fails the turn', () async {
      final sse = _dataLine({
        'error': {'code': 429, 'message': 'rate limited'},
      });
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.streamEvents([ChatMessage.user('hi')]).toList(),
        throwsA(isA<AgentProviderException>()),
      );
    });

    test(
      'a malformed-shape chunk is skipped rather than failing the whole '
      'turn',
      () async {
        final sse = [
          _dataLine({'candidates': 'not-a-list'}),
          _dataLine({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'still works'},
                  ],
                },
              },
            ],
          }),
        ].join();
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse([sse]);
        });
        final provider = GeminiProvider(
          apiKey: 'k',
          model: 'gemini-1.5-flash',
          httpClient: client,
        );
        addTearDown(provider.dispose);

        final events =
            await provider.streamEvents([ChatMessage.user('hi')]).toList();
        expect(events, [const TextDelta('still works')]);
      },
    );

    test(
        'forwards an image attachment as an inlineData part with '
        "Gemini's camelCase field names", () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final message = ChatMessage.user(
        'what is this?',
        attachments: [
          Attachment(
            id: 'a1',
            name: 'photo.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );

      await provider.streamEvents([message]).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final userTurn =
          (body['contents'] as List<Object?>).single as Map<String, Object?>;
      final parts = userTurn['parts'] as List<Object?>;
      expect(parts[0], {'text': 'what is this?'});
      final inlineData =
          (parts[1] as Map<String, Object?>)['inlineData']
              as Map<String, Object?>;
      expect(inlineData['mimeType'], 'image/png');
      expect(base64Decode(inlineData['data'] as String), [1, 2, 3]);
    });

    test('an image attachment with empty (not null) bytes falls back to url',
        () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final message = ChatMessage.user(
        'what is this?',
        attachments: [
          Attachment(
            id: 'a1',
            name: 'photo.png',
            mimeType: 'image/png',
            bytes: Uint8List(0),
            url: 'https://example.com/photo.png',
          ),
        ],
      );

      await provider.streamEvents([message]).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final userTurn =
          (body['contents'] as List<Object?>).single as Map<String, Object?>;
      final parts = userTurn['parts'] as List<Object?>;
      final fileData =
          (parts[1] as Map<String, Object?>)['fileData'] as Map<String, Object?>;
      expect(fileData['fileUri'], 'https://example.com/photo.png');
    });

    test('an attachment with no caption omits the empty text part', () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final message = ChatMessage.user(
        '',
        attachments: [
          Attachment(
            id: 'a1',
            name: 'photo.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );

      await provider.streamEvents([message]).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final userTurn =
          (body['contents'] as List<Object?>).single as Map<String, Object?>;
      final parts = userTurn['parts'] as List<Object?>;
      expect(parts, hasLength(1));
      expect((parts.single as Map<String, Object?>).containsKey('inlineData'), isTrue);
    });

    test(
        'an unfinished tool call is omitted from the functionCall parts '
        'instead of producing an unmatched one, but the turn itself still '
        'appears in history', () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final conversation = [
        ChatMessage.user('what is the weather?'),
        ChatMessage.assistant(
          '',
          toolCalls: const [
            ToolCall(
              id: 'pending-call',
              name: 'get_weather',
              status: ToolCallStatus.pending,
              input: '{"city":"Colombo"}',
            ),
          ],
        ),
      ];

      await provider.streamEvents(conversation).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(2));
      // The assistant turn still appears (dropping it entirely would break
      // Gemini's strict role alternation) with an explicit empty text part,
      // since the one call it made hasn't resolved yet.
      expect(contents[1], {
        'role': 'model',
        'parts': [
          {'text': ''},
        ],
      });
    });

    test('a candidate with an explicitly empty parts list and a non-STOP '
        'finish reason fails the turn', () async {
      final sse = _dataLine({
        'candidates': [
          {
            'content': {'parts': <Object?>[]},
            'finishReason': 'MAX_TOKENS',
          },
        ],
      });
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.streamEvents([ChatMessage.user('hi')]).toList(),
        throwsA(isA<AgentProviderException>()),
      );
    });

    test('a non-2xx response throws AgentProviderException', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'error': {'code': 401, 'message': 'bad key', 'status': 'UNAUTHENTICATED'},
          }))),
          401,
        );
      });
      final provider = GeminiProvider(
        apiKey: 'bad',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.streamEvents([ChatMessage.user('hi')]).toList(),
        throwsA(isA<AgentProviderException>()),
      );
    });

    test('a provider error fails the message via sendMessage', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(utf8.encode('boom')), 500);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final controller = ChatController();
      addTearDown(controller.dispose);

      await provider.sendMessage(controller, 'hi');

      expect(controller.messages.last.status, MessageStatus.failed);
    });

    test('asResponder streams text through a managed ChatController.send()',
        () async {
      final sse = _dataLine({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'hi there'},
              ],
            },
          },
        ],
      });
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      late final ChatController controller;
      controller = ChatController(
        responder: provider.asResponder(history: () => controller.messages),
      );
      addTearDown(controller.dispose);

      await controller.send('hello');

      expect(controller.messages.last.text, 'hi there');
      expect(controller.messages.last.status, MessageStatus.sent);
    });

    test(
        'asResponder still sends the user message when history is omitted '
        'entirely', () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final responder = provider.asResponder(); // no `history:` supplied
      await responder(ChatMessage.user('hello there')).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(1));
      expect(contents.single, {
        'role': 'user',
        'parts': [
          {'text': 'hello there'},
        ],
      });
    });

    test(
        "asResponder does not duplicate the user message when history's "
        'tail is already it', () async {
      String? capturedBody;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['']);
      });
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'gemini-1.5-flash',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final userMessage = ChatMessage.user('hello there');
      final responder = provider.asResponder(history: () => [userMessage]);
      await responder(userMessage).toList();

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(1));
    });

    test('dispose() does not close a caller-supplied http client', () async {
      var closed = false;
      final client = _SpyClient(onClose: () => closed = true);
      final provider = GeminiProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );

      provider.dispose();

      expect(closed, isFalse);
    });
  });
}

class _SpyClient extends http.BaseClient {
  _SpyClient({required this.onClose});

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  void close() => onClose();
}
