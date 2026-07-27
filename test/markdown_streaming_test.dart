import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendering half-formed markdown is the normal case, not an edge case: every
/// prefix of a streamed response gets built at least once. These tests pump
/// each prefix through the real widget tree, which is where widget-level
/// asserts (Table row lengths, for one) surface that a parser-only test
/// cannot catch.
void main() {
  Future<void> streamThrough(WidgetTester tester, String source) async {
    for (var i = 1; i <= source.length; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(data: source.substring(0, i)),
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'threw at prefix length $i:\n${source.substring(0, i)}',
      );
    }
  }

  testWidgets('a table renders at every prefix', (tester) async {
    // The regression: a partially typed row has fewer cells than the header,
    // and Table asserts on irregular row lengths.
    await streamThrough(
      tester,
      '| Feature | Value |\n|---|---:|\n| Latency | 820ms |\n| Tokens | 1204 |',
    );
  });

  testWidgets('a table with a ragged row renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            data: '| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('lists and code render at every prefix', (tester) async {
    await streamThrough(
      tester,
      '# Title\n\n- one\n- two\n\n```dart\nvar x = 1;\n```',
    );
  });

  testWidgets('blockquotes and rules render at every prefix', (tester) async {
    await streamThrough(tester, '> quoted\n\n---\n\n**bold** and `code`');
  });

  testWidgets('task lists and links render at every prefix', (tester) async {
    await streamThrough(
      tester,
      '- [x] done\n- [ ] todo\n\n[docs](https://flutter.dev)',
    );
  });

  testWidgets('a streamed table inside a ChatBubble does not throw',
      (tester) async {
    const source = '| a | b |\n|---|---|\n| 1 | 2 |';
    for (var i = 1; i <= source.length; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: ChatMessage.assistant(
                source.substring(0, i),
                status: MessageStatus.streaming,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'threw at length $i');
    }
  });
}
