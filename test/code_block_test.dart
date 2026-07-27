import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  String lines(int n) =>
      List.generate(n, (i) => 'final x$i = $i;').join('\n');

  group('expand toggle', () {
    testWidgets('is hidden when the snippet fits', (tester) async {
      // The bug: the toggle appeared for any snippet, so tapping "Show more"
      // on short code changed nothing and the label flipped to "Show less",
      // reading as an inverted button.
      await pump(tester, CodeBlock(code: lines(4), language: 'dart'));

      expect(find.text('Show more'), findsNothing);
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('appears when the snippet overflows', (tester) async {
      await pump(tester, CodeBlock(code: lines(60), language: 'dart'));

      expect(find.text('Show more'), findsOneWidget);
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('expands and collapses in the right direction',
        (tester) async {
      await pump(tester, CodeBlock(code: lines(60), language: 'dart'));

      final collapsedHeight = tester.getSize(find.byType(CodeBlock)).height;

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Show less'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CodeBlock)).height,
        greaterThan(collapsedHeight),
        reason: '"Show more" must make the block taller',
      );

      // Expanding pushes the toggle past the bottom of the test viewport, so
      // it has to be scrolled back into view before it can be tapped.
      await tester.ensureVisible(find.text('Show less'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();

      expect(find.text('Show more'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CodeBlock)).height,
        collapsedHeight,
        reason: '"Show less" must restore the collapsed height',
      );
    });

    testWidgets('never collapses when collapsedMaxHeight is null',
        (tester) async {
      await pump(
        tester,
        CodeBlock(
          code: lines(60),
          language: 'dart',
          collapsedMaxHeight: null,
        ),
      );

      expect(find.text('Show more'), findsNothing);
    });
  });

  group('header', () {
    testWidgets('shows the language, or CODE when unknown', (tester) async {
      await pump(tester, const CodeBlock(code: 'x', language: 'python'));
      expect(find.text('PYTHON'), findsOneWidget);

      await pump(tester, const CodeBlock(code: 'x'));
      expect(find.text('CODE'), findsOneWidget);
    });

    testWidgets('can be hidden', (tester) async {
      await pump(tester, const CodeBlock(code: 'x', showHeader: false));
      expect(find.text('Copy'), findsNothing);
    });
  });
}
