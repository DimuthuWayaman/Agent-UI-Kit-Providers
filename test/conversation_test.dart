import 'dart:async';

import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatController responder(List<String> chunks) =>
      ChatController(responder: (_) => Stream.fromIterable(chunks));

  group('Conversation', () {
    test('derives a title from the first user message', () {
      final conversation = Conversation(
        id: 'c1',
        messages: [
          ChatMessage.user('How do I stream tokens in Flutter?'),
          ChatMessage.assistant('Like this...'),
        ],
      );
      expect(conversation.displayTitle, 'How do I stream tokens in Flutter?');
    });

    test('truncates a long title on a word boundary', () {
      final conversation = Conversation(
        id: 'c1',
        messages: [
          ChatMessage.user(
            'Explain in detail how incremental markdown parsing works '
            'during a streamed response',
          ),
        ],
      );
      final title = conversation.displayTitle;
      expect(title.length, lessThanOrEqualTo(41));
      expect(title, endsWith('…'));
      expect(title, isNot(contains('  ')));
    });

    test('an explicit title wins over the derived one', () {
      final conversation = Conversation(
        id: 'c1',
        title: 'Renamed',
        messages: [ChatMessage.user('Original question')],
      );
      expect(conversation.displayTitle, 'Renamed');
    });

    test('falls back to a placeholder when empty', () {
      expect(Conversation(id: 'c1').displayTitle, 'New chat');
      expect(Conversation(id: 'c1').preview, 'No messages yet');
    });
  });

  group('ConversationController', () {
    test('newConversation makes a thread active', () {
      final controller = ConversationController();
      addTearDown(controller.dispose);

      final id = controller.newConversation();
      expect(controller.activeId, id);
      expect(controller.conversations, hasLength(1));
    });

    test('does not stack up empty conversations', () {
      final controller = ConversationController();
      addTearDown(controller.dispose);

      final first = controller.newConversation();
      final second = controller.newConversation();

      expect(second, first, reason: 'an unused thread should be reused');
      expect(controller.conversations, hasLength(1));
    });

    test('mirrors sent messages into the active conversation', () async {
      final controller = ConversationController(chat: responder(['hi']));
      addTearDown(controller.dispose);

      controller.newConversation();
      await controller.chat.send('hello');

      expect(controller.active!.messages, hasLength(2));
      expect(controller.active!.displayTitle, 'hello');
    });

    test('switching threads swaps the live messages', () async {
      final controller = ConversationController(chat: responder(['reply']));
      addTearDown(controller.dispose);

      final first = controller.newConversation();
      await controller.chat.send('first question');

      final second = controller.newConversation();
      expect(controller.chat.messages, isEmpty);

      await controller.chat.send('second question');
      expect(controller.chat.messages.first.text, 'second question');

      controller.select(first);
      expect(controller.chat.messages.first.text, 'first question');

      controller.select(second);
      expect(controller.chat.messages.first.text, 'second question');
    });

    test('does not leak messages between threads on repeated switches',
        () async {
      final controller = ConversationController(chat: responder(['r']));
      addTearDown(controller.dispose);

      final a = controller.newConversation();
      await controller.chat.send('a');
      final b = controller.newConversation();
      await controller.chat.send('b');

      for (var i = 0; i < 3; i++) {
        controller.select(a);
        controller.select(b);
      }

      expect(controller.chat.messages, hasLength(2));
    });

    test('deleting the active thread activates another', () async {
      final controller = ConversationController(chat: responder(['r']));
      addTearDown(controller.dispose);

      final first = controller.newConversation();
      await controller.chat.send('first');
      final second = controller.newConversation();
      await controller.chat.send('second');

      controller.delete(second);

      expect(controller.activeId, first);
      expect(controller.chat.messages.first.text, 'first');
    });

    test('deleting the last thread starts a fresh one', () {
      final controller = ConversationController();
      addTearDown(controller.dispose);

      final id = controller.newConversation();
      controller.delete(id);

      expect(controller.conversations, hasLength(1));
      expect(controller.activeId, isNot(id));
      expect(controller.chat.messages, isEmpty);
    });

    test('rename sets an explicit title', () async {
      final controller = ConversationController(chat: responder(['r']));
      addTearDown(controller.dispose);

      final id = controller.newConversation();
      await controller.chat.send('original');
      controller.rename(id, 'My thread');

      expect(controller.active!.displayTitle, 'My thread');
    });

    test('pinned threads sort to the top', () async {
      final controller = ConversationController(chat: responder(['r']));
      addTearDown(controller.dispose);

      final first = controller.newConversation();
      await controller.chat.send('older');
      controller.newConversation();
      await controller.chat.send('newer');

      expect(controller.conversations.first.messages.first.text, 'newer');

      controller.setPinned(first, true);
      expect(controller.conversations.first.id, first);
    });

    test('search matches titles and message bodies', () async {
      final controller = ConversationController(chat: responder(['r']));
      addTearDown(controller.dispose);

      controller.newConversation();
      await controller.chat.send('flutter streaming');
      controller.newConversation();
      await controller.chat.send('dart isolates');

      expect(controller.search('flutter'), hasLength(1));
      expect(controller.search('ISOLATES'), hasLength(1));
      expect(controller.search(''), hasLength(2));
      expect(controller.search('nothing'), isEmpty);
    });

    test(
      'does not duplicate messages when chat is already populated to match '
      'initialConversations',
      () {
        final chat = ChatController(
          initialMessages: [ChatMessage.user('restored question', id: 'm1')],
        );
        final saved = [Conversation(id: 'c1', messages: chat.messages)];
        final controller = ConversationController(
          chat: chat,
          initialConversations: saved,
        );
        addTearDown(controller.dispose);

        expect(controller.chat.messages, hasLength(1));
      },
    );

    test('self-heals when given an activeId matching no conversation', () {
      final controller = ConversationController(
        initialConversations: [Conversation(id: 'c1')],
        activeId: 'does-not-exist',
      );
      addTearDown(controller.dispose);

      expect(controller.active, isNotNull);
      expect(controller.activeId, isNot('does-not-exist'));
    });

    test('does not bump updatedAt on every streamed token', () async {
      final source = StreamController<String>();
      final controller = ConversationController(
        chat: ChatController(responder: (_) => source.stream),
      );
      addTearDown(controller.dispose);

      controller.newConversation();
      unawaited(controller.chat.send('question'));
      await Future<void>.delayed(Duration.zero);

      final afterBegin = controller.active!.updatedAt;

      source.add('a');
      await Future<void>.delayed(Duration.zero);
      source.add('b');
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.active!.updatedAt,
        afterBegin,
        reason: 'appending tokens mid-stream should not re-timestamp',
      );

      await source.close();
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.active!.updatedAt,
        isNot(afterBegin),
        reason: 'settling out of streaming should bump the timestamp',
      );
    });

    test('restores from persisted conversations', () {
      final saved = [
        Conversation(
          id: 'c1',
          messages: [ChatMessage.user('restored question')],
        ),
      ];
      final controller = ConversationController(initialConversations: saved);
      addTearDown(controller.dispose);

      expect(controller.activeId, 'c1');
      expect(controller.chat.messages.first.text, 'restored question');
    });

    test('groups conversations by recency', () {
      final now = DateTime(2026, 7, 27);
      final groups = groupConversationsByDate(
        [
          Conversation(id: 'a', updatedAt: now),
          Conversation(
            id: 'b',
            updatedAt: now.subtract(const Duration(days: 1)),
          ),
          Conversation(
            id: 'c',
            updatedAt: now.subtract(const Duration(days: 3)),
          ),
          Conversation(
            id: 'd',
            updatedAt: now.subtract(const Duration(days: 60)),
          ),
        ],
        now: now,
      );

      expect(groups['Today'], hasLength(1));
      expect(groups['Yesterday'], hasLength(1));
      expect(groups['Previous 7 days'], hasLength(1));
      expect(groups['Older'], hasLength(1));
    });
  });

  group('ChatController.editMessage', () {
    test('rewrites the prompt and drops everything after it', () async {
      var call = 0;
      final controller = ChatController(
        responder: (_) {
          call++;
          return Stream.fromIterable(['answer $call']);
        },
      );
      addTearDown(controller.dispose);

      await controller.send('frist question');
      final id = controller.messages.first.id;

      await controller.editMessage(id, 'first question');

      expect(controller.messages, hasLength(2));
      expect(controller.messages[0].text, 'first question');
      expect(controller.messages[1].text, 'answer 2');
      expect(
        controller.messages[0].id,
        id,
        reason:
            'a responder-attached edit must keep the original id, the same '
            'as the no-responder path -- callers tracking a message by id '
            'across an edit should see consistent behavior either way',
      );
    });

    test('ignores edits to assistant messages', () async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await controller.send('question');
      final assistantId = controller.messages.last.id;

      await controller.editMessage(assistantId, 'tampered');

      expect(controller.messages.last.text, 'reply');
    });

    test('ignores an unchanged or empty edit', () async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await controller.send('question');
      final id = controller.messages.first.id;

      await controller.editMessage(id, 'question');
      await controller.editMessage(id, '   ');

      expect(controller.messages, hasLength(2));
    });

    test('updates text in place without a responder', () async {
      final controller = ChatController();
      addTearDown(controller.dispose);

      controller.addMessage(ChatMessage.user('typo', id: 'u1'));
      await controller.editMessage('u1', 'fixed');

      expect(controller.messages.single.text, 'fixed');
    });
  });
}
