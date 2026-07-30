import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:agent_ui_kit_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on the menu, not a demo', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    expect(find.text('agent_ui_kit_providers'), findsOneWidget);
    expect(find.text('Chat demo'), findsOneWidget);
    expect(find.text('Widget gallery'), findsOneWidget);

    // Nothing should be competing for vertical space on the demos.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the chat demo opens full screen', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat demo'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('How can I help?'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // Pushed routes get a back affordance to the menu.
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('history stays reachable once the chat is pushed',
      (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat demo'));
    await tester.pumpAndSettle();

    // The back button takes the leading slot, so history moves to an action.
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ChatHistoryDrawer), findsOneWidget);
    expect(find.text('New chat'), findsWidgets);
  });

  testWidgets('the gallery opens full screen', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Widget gallery'));
    // The gallery contains a running spinner and typing dots, which never
    // settle; pump fixed frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('BUBBLES'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a conversation survives returning to the menu', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat demo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me a table'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Rendering support'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Chat demo'), findsOneWidget);

    await tester.tap(find.text('Chat demo'));
    await tester.pumpAndSettle();

    // The controller lives above the route, so the thread is still there.
    expect(find.textContaining('Rendering support'), findsOneWidget);
  });

  testWidgets('the menu does not overflow on a short screen', (tester) async {
    // Regression test: the menu's three cards used to sit in a fixed Column
    // relying on Spacer to absorb any slack. Spacer can shrink to zero but
    // not below it, so a short screen (small phone, or a phone in landscape)
    // overflowed by tens of pixels once a third card was added. The menu is
    // a SingleChildScrollView now, so it should just scroll instead.
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Live provider demo'), findsOneWidget);
  });

  testWidgets('the theme switcher cycles from the menu', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.light_mode_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.blur_on_rounded), findsOneWidget);
  });
}
