import 'dart:async';
import 'dart:convert';

import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.StreamedResponse _sseResponse(
  List<String> chunks, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream.fromIterable(chunks.map(utf8.encode)),
    statusCode,
    headers: {'content-type': 'text/event-stream'},
  );
}

void main() {
  group('OpenRouterProvider', () {
    test('sends model, stream:true and mapped messages, including a '
        'finished tool call round-tripped as a tool message', () async {
      http.BaseRequest? captured;
      String? capturedBody;

      final client = MockClient.streaming((request, bodyStream) async {
        captured = request;
        capturedBody = await bodyStream.transform(utf8.decoder).join();
        return _sseResponse(['data: [DONE]\n\n']);
      });

      final provider = OpenRouterProvider(
        apiKey: 'sk-test',
        model: 'openai/gpt-4o',
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
              id: 'call_1',
              name: 'get_weather',
              status: ToolCallStatus.success,
              input: '{"city":"Colombo"}',
              output: '29C, cloudy',
            ),
          ],
        ),
      ];

      await provider.streamEvents(conversation).toList();

      expect(captured!.url.toString(),
          'https://openrouter.ai/api/v1/chat/completions');
      expect(captured!.headers['Authorization'], 'Bearer sk-test');

      final body = jsonDecode(capturedBody!) as Map<String, Object?>;
      expect(body['model'], 'openai/gpt-4o');
      expect(body['stream'], isTrue);

      final messages = body['messages'] as List<Object?>;
      expect(messages, hasLength(4));
      expect(messages[0], {'role': 'system', 'content': 'be terse'});
      expect(messages[1], {'role': 'user', 'content': 'what is the weather?'});
      final assistantMsg = messages[2] as Map<String, Object?>;
      expect(assistantMsg['role'], 'assistant');
      expect(
        (assistantMsg['tool_calls'] as List<Object?>).single,
        {
          'id': 'call_1',
          'type': 'function',
          'function': {'name': 'get_weather', 'arguments': '{"city":"Colombo"}'},
        },
      );
      expect(messages[3], {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'content': '29C, cloudy',
      });
    });

    test('streams text deltas independent of chunk boundaries', () async {
      const sse =
          'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":", world"}}]}\n\n'
          'data: [DONE]\n\n';
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse.substring(0, 30), sse.substring(30)]);
      });
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final events = await provider.streamEvents([ChatMessage.user('hi')]).toList();
      expect(events, [const TextDelta('Hello'), const TextDelta(', world')]);
    });

    test('accumulates fragmented tool_calls arguments across deltas',
        () async {
      // Built with jsonEncode, not hand-escaped strings, since the
      // "arguments" field is itself a fragment of JSON text delivered as a
      // plain string value -- easy to get wrong by hand.
      Map<String, Object?> deltaChunk(Map<String, Object?> toolCallDelta) => {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {'index': 0, ...toolCallDelta},
                  ],
                },
              },
            ],
          };
      String dataLine(Object json) => 'data: ${jsonEncode(json)}\n\n';

      final sse = [
        dataLine(deltaChunk({
          'id': 'c1',
          'function': {'name': 'get_weather', 'arguments': ''},
        })),
        dataLine(deltaChunk({
          'function': {'arguments': '{"city":'},
        })),
        dataLine(deltaChunk({
          'function': {'arguments': '"Colombo"}'},
        })),
        'data: [DONE]\n\n',
      ].join();

      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final events = await provider.streamEvents([ChatMessage.user('hi')]).toList();
      expect(events, hasLength(1));
      final event = events.single as ToolCallEvent;
      expect(event.call.id, 'c1');
      expect(event.call.name, 'get_weather');
      expect(event.call.status, ToolCallStatus.pending);
      expect(jsonDecode(event.call.input!), {'city': 'Colombo'});
    });

    test('a non-2xx response throws AgentProviderException', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('unauthorized')),
          401,
        );
      });
      final provider = OpenRouterProvider(
        apiKey: 'bad',
        model: 'm',
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
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final controller = ChatController();
      addTearDown(controller.dispose);

      await provider.sendMessage(controller, 'hi');

      expect(controller.messages.last.status, MessageStatus.failed);
      expect(controller.messages.last.error, isNotNull);
    });

    test('asResponder streams text through a managed ChatController.send()',
        () async {
      const sse = 'data: {"choices":[{"delta":{"content":"hi there"}}]}\n\n'
          'data: [DONE]\n\n';
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      late final ChatController controller;
      controller = ChatController(
        responder: provider.asResponder(history: () => controller.messages),
      );
      addTearDown(controller.dispose);

      await controller.send('hello');

      expect(controller.messages.last.role, ChatRole.assistant);
      expect(controller.messages.last.text, 'hi there');
      expect(controller.messages.last.status, MessageStatus.sent);
    });

    test('sendMessage drives tool calls onto the controller', () async {
      const sse = 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"id":"c1","function":{"name":"get_weather","arguments":"{}"}}]}}]}\n\n'
          'data: [DONE]\n\n';
      final client = MockClient.streaming((request, bodyStream) async {
        return _sseResponse([sse]);
      });
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final controller = ChatController();
      addTearDown(controller.dispose);

      await provider.sendMessage(controller, 'weather?');

      final assistant = controller.messages.last;
      expect(assistant.toolCalls, hasLength(1));
      expect(assistant.toolCalls.single.name, 'get_weather');
      expect(assistant.status, MessageStatus.sent);
    });

    test('controller.stop() during sendMessage stops further tokens',
        () async {
      final controllerToken = StreamController<String>();
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          controllerToken.stream.map(utf8.encode),
          200,
        );
      });
      final provider = OpenRouterProvider(
        apiKey: 'k',
        model: 'm',
        httpClient: client,
      );
      addTearDown(provider.dispose);

      final controller = ChatController();
      addTearDown(controller.dispose);

      final done = provider.sendMessage(controller, 'hi');

      controllerToken.add(
        'data: {"choices":[{"delta":{"content":"first"}}]}\n\n',
      );
      // Let the first event propagate before stopping.
      await Future<void>.delayed(Duration.zero);
      expect(controller.messages.last.text, 'first');

      controller.stop();

      controllerToken.add(
        'data: {"choices":[{"delta":{"content":"second"}}]}\n\n',
      );
      await controllerToken.close();
      await done;

      expect(controller.messages.last.text, 'first');
    });

    test('dispose() does not close a caller-supplied http client', () async {
      var closed = false;
      final client = _SpyClient(onClose: () => closed = true);
      final provider = OpenRouterProvider(
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
