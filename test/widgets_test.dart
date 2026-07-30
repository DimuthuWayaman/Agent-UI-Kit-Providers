import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in the minimum scaffolding these widgets need.
Widget host(Widget child, {AgentThemeData? theme}) {
  final app = MaterialApp(
    home: Scaffold(body: child),
  );
  return theme == null ? app : AgentTheme(data: theme, child: app);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Clipboard writes go over a platform channel that has no implementation in
  // tests; without a stub the copy buttons never reach their confirmed state.
  final clipboard = <String, Object?>{};
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard['text'] =
              (call.arguments as Map<Object?, Object?>)['text'];
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    clipboard.clear();
  });
  group('AgentThemeData', () {
    test('implements value equality', () {
      expect(AgentThemeData.light(), AgentThemeData.light());
      expect(AgentThemeData.light().hashCode, AgentThemeData.light().hashCode);
      expect(AgentThemeData.light(), isNot(AgentThemeData.dark()));
    });

    test('copyWith produces an equal object when given nothing', () {
      final theme = AgentThemeData.light();
      expect(theme.copyWith(), theme);
    });

    test('lerp moves between two themes', () {
      final a = AgentThemeData.light();
      final b = AgentThemeData.dark();
      expect(AgentThemeData.lerp(a, b, 0), a);
      expect(AgentThemeData.lerp(a, b, 1), b);

      final mid = AgentThemeData.lerp(a, b, 0.5);
      expect(mid.colors.surface, isNot(a.colors.surface));
      expect(mid.colors.surface, isNot(b.colors.surface));
    });

    testWidgets('of() falls back to the ambient Material theme', (tester) async {
      late AgentThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: Builder(
            builder: (context) {
              resolved = AgentTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved.colors.accent, isNotNull);
      expect(resolved.brightness, Brightness.light);
    });

    testWidgets('maybeOf returns null with no ancestor', (tester) async {
      AgentThemeData? resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = AgentTheme.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved, isNull);
    });
  });

  group('ChatBubble', () {
    testWidgets('renders assistant markdown', (tester) async {
      await tester.pumpWidget(
        host(ChatBubble(message: ChatMessage.assistant('Hello **world**'))),
      );
      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('renders user text without markdown parsing', (tester) async {
      await tester.pumpWidget(
        host(ChatBubble(message: ChatMessage.user('literal *stars*'))),
      );
      expect(find.text('literal *stars*'), findsOneWidget);
    });

    testWidgets('shows a typing indicator while streaming', (tester) async {
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant(
              '',
              status: MessageStatus.streaming,
            ),
          ),
        ),
      );
      expect(find.byType(TypingIndicator), findsOneWidget);
      // An endlessly repeating animation never settles, so pump a fixed
      // number of frames rather than pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('shows the error and retry affordance when failed',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant(
              'partial',
              status: MessageStatus.failed,
            ).copyWith(error: 'Network unreachable'),
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Network unreachable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('shows the response time when completed', (tester) async {
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('done').copyWith(
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(milliseconds: 2300)),
            ),
            showResponseTime: true,
          ),
        ),
      );
      expect(find.text('2.3s'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });

    testWidgets(
        'pins response time to the opposite corner from the timestamp, not '
        'right next to it', (tester) async {
      // The two used to sit adjacent in the same cluster, separated only by
      // a thin "|", which read as one ambiguous run of numbers. They should
      // now anchor to opposite edges of the bubble.
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('done').copyWith(
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(milliseconds: 2300)),
            ),
            showTimestamp: true,
            timestampFormatter: (_) => '9:41 AM',
            showResponseTime: true,
          ),
        ),
      );

      expect(find.text('9:41 AM'), findsOneWidget);
      expect(find.text('2.3s'), findsOneWidget);
      expect(find.text('|'), findsNothing);
      expect(find.textContaining('Responded'), findsNothing);

      final timestampCenter = tester.getCenter(find.text('9:41 AM'));
      final responseTimeCenter = tester.getCenter(find.text('2.3s'));
      expect(
        responseTimeCenter.dx,
        greaterThan(timestampCenter.dx),
        reason: 'response time should sit to the right of the timestamp',
      );
      // Same row, not stacked underneath.
      expect((responseTimeCenter.dy - timestampCenter.dy).abs(), lessThan(4));
    });

    testWidgets('response time honors a custom formatter and icon',
        (tester) async {
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('done').copyWith(
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(seconds: 4)),
            ),
            showResponseTime: true,
            responseTimeFormatter: (d) => '${d.inSeconds}s flat',
            responseTimeIcon: Icons.bolt_rounded,
          ),
        ),
      );
      expect(find.text('4s flat'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
    });

    testWidgets(
        'a long response-time result does not overflow the bubble even '
        'alongside a timestamp', (tester) async {
      // A moderately narrow viewport plus a deliberately long formatter
      // result is what exposed the missing Flexible around the
      // response-time cluster. showActions is deliberately left off here --
      // MessageActionBar's own fixed-width icon row is a separate concern
      // from the bug this test targets.
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('done').copyWith(
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(seconds: 4)),
            ),
            showTimestamp: true,
            showResponseTime: true,
            responseTimeFormatter: (_) =>
                'a very long response time label that would not normally fit',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the response time until showResponseTime is set',
        (tester) async {
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('done').copyWith(
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(seconds: 1)),
            ),
          ),
        ),
      );
      expect(find.text('1.0s'), findsNothing);
    });

    testWidgets('shows an interrupted indicator when stopped', (tester) async {
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('partial answer').copyWith(
              status: MessageStatus.stopped,
              createdAt: createdAt,
              completedAt: createdAt.add(const Duration(milliseconds: 3400)),
            ),
          ),
        ),
      );
      expect(find.text('Interrupted after 3.4s'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('interrupted indicator honors a custom formatter and icon',
        (tester) async {
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('partial').copyWith(
              status: MessageStatus.stopped,
            ),
            interruptedFormatter: (_) => 'Cut off',
            interruptedIcon: Icons.pause_circle_outline,
          ),
        ),
      );
      expect(find.text('Cut off'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    });

    testWidgets('does not show an interrupted indicator for a normal reply',
        (tester) async {
      await tester.pumpWidget(
        host(ChatBubble(message: ChatMessage.assistant('done'))),
      );
      expect(find.textContaining('Interrupted'), findsNothing);
    });

    testWidgets('renders a system message centered', (tester) async {
      await tester.pumpWidget(
        host(ChatBubble(message: ChatMessage.system('Context cleared'))),
      );
      expect(find.text('Context cleared'), findsOneWidget);
    });

    testWidgets('ChatBubble.text builds a message', (tester) async {
      await tester.pumpWidget(
        host(ChatBubble.text('quick', role: ChatRole.user)),
      );
      expect(find.text('quick'), findsOneWidget);
    });

    testWidgets(
        'actions and timestamp render on the same row, directly under the '
        'bubble', (tester) async {
      // Geometry check, not just presence -- this is exactly what was
      // reported as still wrong after the Column-to-Row footer change, so
      // assert actual pixel positions rather than trusting the widget tree
      // shape alone.
      await tester.pumpWidget(
        host(
          ChatBubble(
            message: ChatMessage.assistant('Hello'),
            showActions: true,
            showTimestamp: true,
            timestampFormatter: (_) => '9:41 AM',
            onRegenerate: () {},
            onFeedback: (_) {},
          ),
        ),
      );

      final actionBarCenter =
          tester.getCenter(find.byType(MessageActionBar));
      final timestampCenter = tester.getCenter(find.text('9:41 AM'));

      // Same row: near-equal vertical center. Generous tolerance for the
      // icon (28dp) vs text glyph height difference, but nowhere near what
      // a full row of vertical stacking (~28dp+) would produce.
      expect(
        (actionBarCenter.dy - timestampCenter.dy).abs(),
        lessThan(10),
      );
      // Side by side, not stacked: the action bar must sit to the left of
      // the timestamp on the same line.
      expect(actionBarCenter.dx, lessThan(timestampCenter.dx));

      // Close to the bubble: gap between the bubble's bottom edge and the
      // footer's top edge should be small (a couple of theme.spacing.xs),
      // not the old double-padding amount.
      final bubbleBottom =
          tester.getBottomLeft(find.byType(MarkdownView)).dy;
      final footerTop = tester.getTopLeft(find.byType(MessageActionBar)).dy;
      expect(footerTop - bubbleBottom, lessThan(24));
    });
  });

  group('ToolCallCard', () {
    testWidgets('shows the tool name and expands to reveal details',
        (tester) async {
      await tester.pumpWidget(
        host(
          const ToolCallCard(
            toolCall: ToolCall(
              id: 't1',
              name: 'get_weather',
              status: ToolCallStatus.success,
              input: '{"city":"Colombo"}',
              output: '{"tempC":29}',
            ),
          ),
        ),
      );

      expect(find.text('get_weather'), findsOneWidget);
      expect(find.text('INPUT'), findsNothing);

      await tester.tap(find.text('get_weather'));
      await tester.pumpAndSettle();

      expect(find.text('INPUT'), findsOneWidget);
      expect(find.text('OUTPUT'), findsOneWidget);
    });

    testWidgets('auto-expands a failed call', (tester) async {
      await tester.pumpWidget(
        host(
          const ToolCallCard(
            toolCall: ToolCall(
              id: 't1',
              name: 'search',
              status: ToolCallStatus.error,
              error: 'rate limited',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('rate limited'), findsOneWidget);
    });

    testWidgets('does not expand when there are no details', (tester) async {
      await tester.pumpWidget(
        host(
          const ToolCallCard(
            toolCall: ToolCall(
              id: 't1',
              name: 'noop',
              status: ToolCallStatus.success,
            ),
          ),
        ),
      );
      await tester.tap(find.text('noop'));
      await tester.pumpAndSettle();
      expect(find.text('INPUT'), findsNothing);
    });
  });

  group('ChatInputBar', () {
    testWidgets('sends trimmed text and clears the field', (tester) async {
      String? sent;
      await tester.pumpWidget(
        host(ChatInputBar(onSend: (text) => sent = text)),
      );

      await tester.enterText(find.byType(TextField), '  hello  ');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sent, 'hello');
      expect(find.text('  hello  '), findsNothing);
    });

    testWidgets('does not send when empty', (tester) async {
      var sends = 0;
      await tester.pumpWidget(host(ChatInputBar(onSend: (_) => sends++)));

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sends, 0);
    });

    testWidgets('shows a stop button while streaming', (tester) async {
      var stopped = false;
      await tester.pumpWidget(
        host(
          ChatInputBar(
            onSend: (_) {},
            isStreaming: true,
            onStop: () => stopped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      expect(stopped, isTrue);
    });

    testWidgets('does not dispose an externally supplied controller',
        (tester) async {
      final controller = TextEditingController(text: 'draft');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(ChatInputBar(onSend: (_) {}, controller: controller)),
      );
      await tester.pumpWidget(const SizedBox());

      // Would throw if ChatInputBar had disposed it.
      expect(controller.text, 'draft');
    });

    testWidgets('renders the attach button only when wired up', (tester) async {
      await tester.pumpWidget(host(ChatInputBar(onSend: (_) {})));
      expect(find.byIcon(Icons.add_rounded), findsNothing);

      await tester.pumpWidget(
        host(ChatInputBar(onSend: (_) {}, onAttach: () {})),
      );
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets(
        'the character counter updates on every keystroke, not only when '
        'crossing empty/non-empty', (tester) async {
      await tester.pumpWidget(
        host(ChatInputBar(onSend: (_) {}, maxLength: 20)),
      );

      // 16 chars = 80% of 20, the threshold where the counter appears.
      await tester.enterText(find.byType(TextField), '1234567890123456');
      await tester.pump();
      expect(find.text('16 / 20'), findsOneWidget);

      // A further keystroke never flips hasText (already non-empty both
      // times) -- this is exactly the case the old code missed.
      await tester.enterText(find.byType(TextField), '12345678901234567');
      await tester.pump();
      expect(find.text('17 / 20'), findsOneWidget);
      expect(find.text('16 / 20'), findsNothing);
    });

    testWidgets(
        'does not double-submit an attachment-only send from a rapid second '
        'tap', (tester) async {
      var sendCount = 0;
      final sentTexts = <String>[];
      await tester.pumpWidget(
        host(
          ChatInputBar(
            onSend: (text) {
              sendCount++;
              sentTexts.add(text);
            },
            attachments: [Attachment(id: 'a1', name: 'photo.png')],
            // Deliberately a no-op: simulates the parent not having rebuilt
            // (and thus not yet reflecting the removal in) widget.attachments
            // between the two taps below.
            onRemoveAttachment: (_) {},
          ),
        ),
      );

      final sendButton = find.byIcon(Icons.arrow_upward_rounded);
      await tester.tap(sendButton);
      await tester.tap(sendButton);
      await tester.pump();

      expect(sendCount, 1);
      expect(sentTexts, ['']);
    });
  });

  group('MessageList', () {
    testWidgets('shows the empty state with no messages', (tester) async {
      await tester.pumpWidget(
        host(
          const MessageList(
            messages: [],
            emptyState: Text('Nothing here'),
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('renders one bubble per message', (tester) async {
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [
              ChatMessage.user('one'),
              ChatMessage.assistant('two'),
            ],
          ),
        ),
      );
      expect(find.byType(ChatBubble), findsNWidgets(2));
    });

    testWidgets('uses messageBuilder overrides', (tester) async {
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [ChatMessage.user('one')],
            messageBuilder: (context, message) => Text('custom ${message.text}'),
          ),
        ),
      );
      expect(find.text('custom one'), findsOneWidget);
      expect(find.byType(ChatBubble), findsNothing);
    });

    testWidgets('shows userAvatar and agentAvatar per role', (tester) async {
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [
              ChatMessage.user('hi', id: 'u1'),
              ChatMessage.assistant('hello', id: 'a1'),
            ],
            userAvatar: const Icon(Icons.face_rounded, key: Key('user-av')),
            agentAvatar: const Icon(Icons.smart_toy_rounded, key: Key('agent-av')),
          ),
        ),
      );

      expect(find.byKey(const Key('user-av')), findsOneWidget);
      expect(find.byKey(const Key('agent-av')), findsOneWidget);
    });

    testWidgets('avatarBuilder overrides userAvatar/agentAvatar',
        (tester) async {
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [ChatMessage.user('hi', id: 'u1')],
            userAvatar: const Icon(Icons.face_rounded, key: Key('fixed')),
            avatarBuilder: (context, message) =>
                const Icon(Icons.star_rounded, key: Key('dynamic')),
          ),
        ),
      );

      expect(find.byKey(const Key('dynamic')), findsOneWidget);
      expect(find.byKey(const Key('fixed')), findsNothing);
    });

    testWidgets(
        'does not reserve avatar space for a role with no avatar of its own',
        (tester) async {
      // Only agentAvatar is set. The user bubble must NOT reserve room for
      // it -- that reservation used to be keyed off "is any avatar source
      // configured at all", which left unwanted empty space beside every
      // user bubble even though the user role never shows an avatar.
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [
              ChatMessage.user('hi', id: 'u1'),
              ChatMessage.assistant('hello', id: 'a1'),
            ],
            agentAvatar: const Icon(Icons.smart_toy_rounded),
          ),
        ),
      );

      final userBubble = tester.widget<ChatBubble>(
        find.byWidgetPredicate(
          (w) => w is ChatBubble && w.message.role == ChatRole.user,
        ),
      );
      expect(userBubble.reserveAvatarSpace, isFalse);
    });

    testWidgets(
        'reserves avatar space within a run for the role that has one',
        (tester) async {
      // Two consecutive assistant messages with agentAvatar set: only the
      // last carries the avatar, but the first must still reserve its width
      // so the pair stays aligned with each other.
      await tester.pumpWidget(
        host(
          MessageList(
            messages: [
              ChatMessage.assistant('first', id: 'a1'),
              ChatMessage.assistant('second', id: 'a2'),
            ],
            agentAvatar: const Icon(Icons.smart_toy_rounded),
          ),
        ),
      );

      final first = tester.widget<ChatBubble>(
        find.byKey(const ValueKey('a1')),
      );
      final second = tester.widget<ChatBubble>(
        find.byKey(const ValueKey('a2')),
      );
      expect(first.reserveAvatarSpace, isTrue);
      expect(first.avatar, isNull);
      expect(second.reserveAvatarSpace, isFalse);
      expect(second.avatar, isNotNull);
    });

    testWidgets('showAvatars: false on ChatScreen reserves no avatar space',
        (tester) async {
      final controller = ChatController(
        initialMessages: [
          ChatMessage.user('hi', id: 'u1'),
          ChatMessage.assistant('hello', id: 'a1'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(controller: controller, showAvatars: false),
        ),
      );

      final bubbles = tester.widgetList<ChatBubble>(find.byType(ChatBubble));
      for (final bubble in bubbles) {
        expect(bubble.reserveAvatarSpace, isFalse);
        expect(bubble.avatar, isNull);
      }
    });
  });

  group('CodeBlock', () {
    testWidgets('shows the language label and copy button', (tester) async {
      await tester.pumpWidget(
        host(const CodeBlock(code: 'var x = 1;', language: 'dart')),
      );
      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('copies to the clipboard and confirms', (tester) async {
      await tester.pumpWidget(
        host(const CodeBlock(code: 'var x = 1;', language: 'dart')),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(clipboard['text'], 'var x = 1;');
      expect(find.text('Copied'), findsOneWidget);

      // The confirmation reverts so the button reads as reusable.
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('SuggestionChips', () {
    testWidgets('reports the chosen suggestion', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        host(
          SuggestionChips(
            suggestions: const [Suggestion('Summarize', value: 'summarize it')],
            onSelected: (value) => chosen = value,
          ),
        ),
      );

      await tester.tap(find.text('Summarize'));
      expect(chosen, 'summarize it');
    });

    testWidgets('renders nothing when empty', (tester) async {
      await tester.pumpWidget(
        host(SuggestionChips(suggestions: const [], onSelected: (_) {})),
      );
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('AgentAvatar', () {
    testWidgets('renders initials when given', (tester) async {
      await tester.pumpWidget(
        host(const AgentAvatar(role: ChatRole.user, initials: 'dimuthu w')),
      );
      expect(find.text('DW'), findsOneWidget);
    });

    testWidgets('falls back to a role icon', (tester) async {
      await tester.pumpWidget(
        host(const AgentAvatar(role: ChatRole.assistant)),
      );
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });
  });

  group('MarkdownView', () {
    testWidgets('renders a code block for a fence', (tester) async {
      await tester.pumpWidget(
        host(const MarkdownView(data: '```dart\nvar x = 1;\n```')),
      );
      expect(find.byType(CodeBlock), findsOneWidget);
    });

    testWidgets('invokes onLinkTap', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        host(
          MarkdownView(
            data: '[docs](https://flutter.dev)',
            onLinkTap: (url) => tapped = url,
          ),
        ),
      );

      // tap() would hit the centre of the paragraph, which is blank space to
      // the right of such short text; tapOnText targets the glyphs.
      await tester.tapOnText(find.textRange.ofSubstring('docs'));
      await tester.pump();
      expect(tapped, 'https://flutter.dev');
    });

    testWidgets('renders a table', (tester) async {
      await tester.pumpWidget(
        host(const MarkdownView(data: '| a | b |\n|---|---|\n| 1 | 2 |')),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('a'), findsWidgets);
    });

    testWidgets('grows without error as text streams in', (tester) async {
      const full = '# Title\n\nSome **text**\n\n- a\n- b';
      for (var i = 1; i <= full.length; i++) {
        await tester.pumpWidget(host(MarkdownView(data: full.substring(0, i))));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatEmptyState', () {
    testWidgets('shows title, subtitle and starters', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        host(
          ChatEmptyState(
            title: 'How can I help?',
            subtitle: 'Ask me anything',
            suggestions: const [Suggestion('Start')],
            onSuggestionSelected: (value) => chosen = value,
          ),
        ),
      );

      expect(find.text('How can I help?'), findsOneWidget);
      expect(find.text('Ask me anything'), findsOneWidget);

      await tester.tap(find.text('Start'));
      expect(chosen, 'Start');
    });
  });

  group('ChatScreen', () {
    testWidgets('sends through the controller and renders the reply',
        (tester) async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['Hi ', 'there']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(controller: controller, title: 'Agent')),
      );

      expect(find.text('How can I help?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(find.textContaining('Hi there'), findsOneWidget);
    });

    testWidgets(
        'through the full ChatScreen path, actions and timestamp still '
        'land on the same row', (tester) async {
      // Reproduces the example app's chat demo config exactly: showTimestamps
      // true, showActions defaulted on, feedback wired so the assistant
      // reply's action bar actually renders (an empty MessageActionBar would
      // make this check trivially pass for the wrong reason).
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            controller: controller,
            title: 'Agent',
            showTimestamps: true,
            onFeedback: (_, __) {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      final assistantBubble = find.byWidgetPredicate(
        (w) => w is ChatBubble && w.message.role == ChatRole.assistant,
      );
      expect(assistantBubble, findsOneWidget);

      final actionBar = find.descendant(
        of: assistantBubble,
        matching: find.byType(MessageActionBar),
      );
      expect(actionBar, findsOneWidget);
      final actionBarCenter = tester.getCenter(actionBar);

      final timestampFinder = find.descendant(
        of: assistantBubble,
        matching: find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d{2}:\d{2}$').hasMatch(w.data ?? ''),
        ),
      );
      expect(timestampFinder, findsOneWidget);
      final timestampCenter = tester.getCenter(timestampFinder);

      expect(
        (actionBarCenter.dy - timestampCenter.dy).abs(),
        lessThan(10),
        reason: 'action bar and timestamp should be on the same row',
      );
    });

    testWidgets('shows a default assistant avatar but no user avatar',
        (tester) async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(controller: controller, title: 'Agent')),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // Preserves the pre-existing default: an assistant icon by default,
      // no user avatar unless one is explicitly supplied.
      expect(find.byType(AgentAvatar), findsOneWidget);

      // The default assistant avatar must not make the user bubble reserve
      // matching space on its own (right) side -- this is the exact
      // no-params ChatScreen(controller: ...) configuration the example
      // app's live-provider demo uses.
      final userBubble = tester.widget<ChatBubble>(
        find.byWidgetPredicate(
          (w) => w is ChatBubble && w.message.role == ChatRole.user,
        ),
      );
      expect(userBubble.reserveAvatarSpace, isFalse);
      expect(userBubble.avatar, isNull);
    });

    testWidgets('userAvatar and agentAvatar render for their roles',
        (tester) async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            controller: controller,
            title: 'Agent',
            userAvatar: const Icon(Icons.face_rounded, key: Key('user-av')),
            agentAvatar:
                const Icon(Icons.smart_toy_rounded, key: Key('agent-av')),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user-av')), findsOneWidget);
      expect(find.byKey(const Key('agent-av')), findsOneWidget);
      // The custom agent avatar replaces the default, rather than both
      // appearing.
      expect(find.byType(AgentAvatar), findsNothing);
    });

    testWidgets('showAvatars: false suppresses custom avatars too',
        (tester) async {
      final controller = ChatController(
        responder: (_) => Stream.fromIterable(['reply']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            controller: controller,
            title: 'Agent',
            showAvatars: false,
            userAvatar: const Icon(Icons.face_rounded, key: Key('user-av')),
            agentAvatar:
                const Icon(Icons.smart_toy_rounded, key: Key('agent-av')),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user-av')), findsNothing);
      expect(find.byKey(const Key('agent-av')), findsNothing);
    });
  });
}
