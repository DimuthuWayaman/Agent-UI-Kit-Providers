import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatController echoController() => ChatController(
        responder: (m) => Stream.fromIterable(['reply to ${m.text}']),
      );

  Widget screen(ChatScreen child) => MaterialApp(home: child);

  group('prompt editing', () {
    testWidgets('an edit button appears on user messages only',
        (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(ChatScreen(controller: controller, title: 'Agent')),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // One edit button, on the single user message.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      // Regenerate belongs to the assistant reply, not the prompt.
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('editing swaps the bubble for an inline editor',
        (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(ChatScreen(controller: controller, title: 'Agent')),
      );

      await tester.enterText(find.byType(TextField), 'frist');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(MessageEditor), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('cancelling restores the bubble unchanged', (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(ChatScreen(controller: controller, title: 'Agent')),
      );

      await tester.enterText(find.byType(TextField), 'original');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(MessageEditor), findsNothing);
      expect(controller.messages.first.text, 'original');
    });

    testWidgets('submitting rewrites the prompt and regenerates',
        (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(ChatScreen(controller: controller, title: 'Agent')),
      );

      await tester.enterText(find.byType(TextField), 'frist');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(MessageEditor),
          matching: find.byType(TextField),
        ),
        'first',
      );
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.text, 'first');
      expect(controller.messages.last.text, 'reply to first');
    });

    testWidgets('allowEditing: false hides the affordance', (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(
          ChatScreen(
            controller: controller,
            title: 'Agent',
            allowEditing: false,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('new chat and history', () {
    testWidgets('the new-chat action clears the thread', (tester) async {
      final conversations = ConversationController(chat: echoController());
      addTearDown(conversations.dispose);

      await tester.pumpWidget(
        screen(
          ChatScreen(
            controller: conversations.chat,
            conversations: conversations,
            title: 'Agent',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(conversations.chat.messages, isNotEmpty);

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      expect(conversations.chat.messages, isEmpty);
      expect(conversations.conversations, hasLength(2));
    });

    testWidgets('the drawer lists past chats and switches between them',
        (tester) async {
      final conversations = ConversationController(chat: echoController());
      addTearDown(conversations.dispose);

      await tester.pumpWidget(
        screen(
          ChatScreen(
            controller: conversations.chat,
            conversations: conversations,
            title: 'Agent',
          ),
        ),
      );

      Future<void> send(String text) async {
        await tester.enterText(find.byType(TextField).first, text);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pumpAndSettle();
      }

      await send('first topic');
      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();
      await send('second topic');

      // Open the drawer via the automatically supplied menu button.
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      // Scope to the drawer: the thread titles also appear as message
      // bubbles behind it, so an unscoped finder matches twice.
      Finder inDrawer(String text) => find.descendant(
            of: find.byType(ChatHistoryDrawer),
            matching: find.text(text),
          );

      expect(inDrawer('New chat'), findsOneWidget);
      expect(inDrawer('first topic'), findsOneWidget);
      expect(inDrawer('second topic'), findsOneWidget);

      await tester.tap(inDrawer('first topic'));
      await tester.pumpAndSettle();

      expect(conversations.chat.messages.first.text, 'first topic');
    });

    testWidgets('no drawer or new-chat action without a history controller',
        (tester) async {
      final controller = echoController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        screen(ChatScreen(controller: controller, title: 'Agent')),
      );

      expect(find.byType(ChatHistoryDrawer), findsNothing);
      expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
    });

    testWidgets('a fresh controller shows a single placeholder thread',
        (tester) async {
      final conversations = ConversationController();
      addTearDown(conversations.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ChatHistoryDrawer(controller: conversations),
            body: const SizedBox(),
          ),
        ),
      );

      await tester.dragFrom(const Offset(2, 300), const Offset(300, 0));
      await tester.pumpAndSettle();

      // One active thread always exists so sent messages have somewhere to
      // go; it renders under its placeholder title alongside the New chat
      // button.
      expect(find.text('New chat'), findsNWidgets(2));
      expect(find.text('No matching chats'), findsNothing);
    });

    testWidgets('searching with no matches shows the empty state',
        (tester) async {
      final conversations = ConversationController(
        initialConversations: [
          for (var i = 0; i < 8; i++)
            Conversation(
              id: 'c$i',
              messages: [ChatMessage.user('topic $i')],
            ),
        ],
      );
      addTearDown(conversations.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ChatHistoryDrawer(controller: conversations),
            body: const SizedBox(),
          ),
        ),
      );

      await tester.dragFrom(const Offset(2, 300), const Offset(300, 0));
      await tester.pumpAndSettle();

      // Search only appears past the threshold, which these eight cross.
      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(find.text('No matching chats'), findsOneWidget);
    });
  });
}
