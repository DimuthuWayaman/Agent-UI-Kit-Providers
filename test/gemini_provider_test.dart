import 'dart:convert';

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
