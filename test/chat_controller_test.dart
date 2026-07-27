import 'dart:async';

import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatController', () {
    test('starts empty', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      expect(controller.isEmpty, isTrue);
      expect(controller.isStreaming, isFalse);
      expect(controller.lastMessage, isNull);
    });

    test('adds messages and notifies listeners', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.addMessage(ChatMessage.user('hi'));
      expect(controller.messages, hasLength(1));
      expect(notifications, 1);
    });

    test('exposes an unmodifiable message list', () {
      final controller = ChatController();
      addTearDown(controller.dispose);
      controller.addMessage(ChatMessage.user('hi'));

      expect(
        () => controller.messages.add(ChatMessage.user('nope')),
        throwsUnsupportedError,
      );
    });

    test('appends tokens to a streaming message', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      final id = controller.beginAssistantMessage();
      expect(controller.isStreaming, isTrue);

      controller.appendToken(id, 'Hel');
      controller.appendToken(id, 'lo');
      expect(controller.messageById(id)!.text, 'Hello');

      controller.completeMessage(id);
      expect(controller.isStreaming, isFalse);
      expect(controller.messageById(id)!.status, MessageStatus.sent);
    });

    test('ignores updates for a message that no longer exists', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      // A late stream event after the message was removed must not throw.
      expect(() => controller.appendToken('ghost', 'x'), returnsNormally);
      expect(controller.messages, isEmpty);
    });

    test('streams a response through a responder', () async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['a', 'b', 'c']),
      );
      addTearDown(controller.dispose);

      await controller.send('question');

      expect(controller.messages, hasLength(2));
      expect(controller.messages[0].role, ChatRole.user);
      expect(controller.messages[1].text, 'abc');
      expect(controller.messages[1].status, MessageStatus.sent);
      expect(controller.isStreaming, isFalse);
    });

    test('marks the message failed when the stream errors', () async {
      final controller = ChatController(
        responder: (_) => Stream<String>.error(Exception('boom')),
      );
      addTearDown(controller.dispose);

      await controller.send('question');

      final reply = controller.messages.last;
      expect(reply.status, MessageStatus.failed);
      expect(reply.error, contains('boom'));
      expect(controller.isStreaming, isFalse);
    });

    test('stop keeps partial text and ends streaming', () async {
      final source = StreamController<String>();
      final controller = ChatController(responder: (_) => source.stream);
      addTearDown(controller.dispose);

      unawaited(controller.send('question'));
      await Future<void>.delayed(Duration.zero);

      source.add('partial');
      await Future<void>.delayed(Duration.zero);

      controller.stop();

      expect(controller.isStreaming, isFalse);
      expect(controller.messages.last.text, 'partial');
      expect(controller.messages.last.status, MessageStatus.sent);

      await source.close();
    });

    test('stop marks unfinished tool calls cancelled', () async {
      final source = StreamController<String>();
      final controller = ChatController(responder: (_) => source.stream);
      addTearDown(controller.dispose);

      unawaited(controller.send('question'));
      await Future<void>.delayed(Duration.zero);

      final id = controller.streamingMessageId!;
      controller.upsertToolCall(
        id,
        const ToolCall(id: 't1', name: 'search', status: ToolCallStatus.running),
      );

      controller.stop();

      expect(
        controller.messageById(id)!.toolCalls.single.status,
        ToolCallStatus.cancelled,
      );
      await source.close();
    });

    test('upsertToolCall replaces a call with the same id', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      final id = controller.beginAssistantMessage();
      controller.upsertToolCall(id, const ToolCall(id: 't1', name: 'search'));
      controller.upsertToolCall(
        id,
        const ToolCall(
          id: 't1',
          name: 'search',
          status: ToolCallStatus.success,
        ),
      );

      final calls = controller.messageById(id)!.toolCalls;
      expect(calls, hasLength(1));
      expect(calls.single.status, ToolCallStatus.success);
    });

    test('send throws without a responder', () {
      final controller = ChatController();
      addTearDown(controller.dispose);

      expect(() => controller.send('hi'), throwsStateError);
    });

    test('ignores an empty send', () async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['x']),
      );
      addTearDown(controller.dispose);

      await controller.send('   ');
      expect(controller.messages, isEmpty);
    });

    test('retryLast removes the failed reply and re-sends', () async {
      var attempt = 0;
      final controller = ChatController(
        responder: (_) {
          attempt++;
          return Stream.fromIterable(['reply $attempt']);
        },
      );
      addTearDown(controller.dispose);

      await controller.send('question');
      await controller.retryLast();

      expect(attempt, 2);
      expect(controller.messages, hasLength(2));
      expect(controller.messages.last.text, 'reply 2');
    });

    test('does not notify after disposal', () async {
      final source = StreamController<String>();
      final controller = ChatController(responder: (_) => source.stream);

      unawaited(controller.send('question'));
      await Future<void>.delayed(Duration.zero);

      controller.dispose();

      // A chunk arriving after disposal must not throw.
      source.add('late');
      await Future<void>.delayed(Duration.zero);
      await source.close();
    });
  });

  group('ChatMessage', () {
    test('appendText accumulates rather than replacing', () {
      final message = ChatMessage.assistant('a').appendText('b');
      expect(message.text, 'ab');
    });

    test('defaults isMarkdown by role', () {
      expect(ChatMessage.user('*x*').isMarkdown, isFalse);
      expect(ChatMessage.assistant('*x*').isMarkdown, isTrue);
    });

    test('isEmpty accounts for tool calls', () {
      final bare = ChatMessage.assistant('');
      expect(bare.isEmpty, isTrue);

      final withTool = bare.upsertToolCall(
        const ToolCall(id: 't', name: 'search'),
      );
      expect(withTool.isEmpty, isFalse);
    });

    test('generates unique ids', () {
      final ids = List.generate(500, (_) => ChatMessage.user('x').id).toSet();
      expect(ids, hasLength(500));
    });
  });

  group('ToolCall', () {
    test('formats duration compactly', () {
      final start = DateTime(2026);
      expect(
        ToolCall(
          id: 't',
          name: 'n',
          startedAt: start,
          completedAt: start.add(const Duration(milliseconds: 820)),
        ).readableDuration,
        '820ms',
      );
      expect(
        ToolCall(
          id: 't',
          name: 'n',
          startedAt: start,
          completedAt: start.add(const Duration(milliseconds: 2400)),
        ).readableDuration,
        '2.4s',
      );
    });

    test('reports terminal states', () {
      const running = ToolCall(id: 't', name: 'n', status: ToolCallStatus.running);
      const done = ToolCall(id: 't', name: 'n', status: ToolCallStatus.success);
      expect(running.isFinished, isFalse);
      expect(done.isFinished, isTrue);
    });
  });

  group('Attachment', () {
    test('infers kind from mime type and extension', () {
      expect(
        Attachment(id: '1', name: 'a.bin', mimeType: 'image/png').kind,
        AttachmentKind.image,
      );
      expect(
        Attachment(id: '2', name: 'report.pdf').kind,
        AttachmentKind.document,
      );
      expect(Attachment(id: '3', name: 'clip.mp4').kind, AttachmentKind.video);
      expect(Attachment(id: '4', name: 'thing.xyz').kind, AttachmentKind.other);
    });

    test('formats readable sizes', () {
      expect(Attachment(id: '1', name: 'a', sizeBytes: 512).readableSize, '512 B');
      expect(
        Attachment(id: '1', name: 'a', sizeBytes: 2048).readableSize,
        '2.0 KB',
      );
    });
  });

  group('Citation', () {
    test('displayLabel strips scheme and www', () {
      const citation = Citation(
        id: '1',
        title: 'Docs',
        url: 'https://www.flutter.dev/docs',
      );
      expect(citation.displayLabel, 'flutter.dev');
    });

    test('falls back to the title without a URL', () {
      const citation = Citation(id: '1', title: 'Internal note');
      expect(citation.displayLabel, 'Internal note');
    });
  });
}
