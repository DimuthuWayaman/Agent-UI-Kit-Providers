import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A SelectionArea placed above a Scrollable installs an auto-scroller that
/// asserts the drag target fits inside the viewport. Once a single message is
/// taller than the screen that assert fires and the app crashes with
/// "Drag target size is larger than scrollable size". Selection is therefore
/// scoped to individual bubbles.
void main() {
  // A reply far taller than the 600px test viewport.
  final tallMessage = ChatMessage.assistant(
    List.generate(80, (i) => 'Line $i of a very long streamed answer.')
        .join('\n\n'),
  );

  testWidgets('no SelectionArea sits above the scrollable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageList(messages: [tallMessage])),
      ),
    );

    final scrollable = find.byType(Scrollable).first;
    expect(
      find.ancestor(of: scrollable, matching: find.byType(SelectionArea)),
      findsNothing,
      reason: 'a SelectionArea above the Scrollable crashes on drag-select',
    );
  });

  testWidgets('bubbles are still individually selectable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageList(messages: [tallMessage])),
      ),
    );

    // Each bubble is wrapped by its own SelectionArea, so the area is the
    // bubble's ancestor — and still a descendant of the Scrollable.
    expect(
      find.ancestor(
        of: find.byType(ChatBubble).first,
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selectable: false drops the selection wrappers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageList(messages: [tallMessage], selectable: false),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('drag-selecting an over-tall message does not throw',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageList(messages: [tallMessage])),
      ),
    );
    await tester.pump();

    // Long-press then drag toward the edge — the gesture that triggered the
    // auto-scroller assertion in the crash report.
    final gesture = await tester.startGesture(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 600));
    for (var dy = 0; dy < 6; dy++) {
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the list still scrolls with selection scoped per bubble',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: [
              for (var i = 0; i < 20; i++)
                ChatMessage.user('Message number $i', id: 'm$i'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final before = position.pixels;

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    expect(position.pixels, greaterThan(before));
  });
}
