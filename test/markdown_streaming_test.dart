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
    MarkdownParseResult? cache;
    for (var i = 1; i <= source.length; i++) {
      final prefix = source.substring(0, i);

      // The core streaming contract: resuming from a cached prior parse must
      // produce exactly what a full reparse of the same text would. A
      // widget-level "did it crash" check alone would miss a silent
      // wrong-content regression here.
      cache = MarkdownParser.parseIncremental(prefix, cache);
      expect(
        _canonBlocks(cache.blocks),
        equals(_canonBlocks(MarkdownParser.parse(prefix))),
        reason:
            'incremental parse diverged from a full reparse at prefix '
            'length $i:\n$prefix',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(data: prefix),
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'threw at prefix length $i:\n$prefix',
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

  test('a paragraph directly touching a table becomes a table', () {
    // No blank line between "intro" and the table header -- the paragraph
    // loop used to swallow the header/delimiter/row as plain text instead of
    // breaking for the table.
    const source = 'intro\ncol1 | col2\n---|---\nval1 | val2';
    final blocks = MarkdownParser.parse(source);
    expect(
      blocks.whereType<MdTable>(),
      isNotEmpty,
      reason: 'table was swallowed into a paragraph: $blocks',
    );
  });

  group('streaming: true renders ambiguous trailing syntax optimistically',
      () {
    test('an unclosed bold span renders as emphasis, not literal asterisks',
        () {
      final blocks = MarkdownParser.parse('Some **bold', streaming: true);
      final spans = (blocks.single as MdParagraph).spans;
      expect(spans, hasLength(2));
      expect(spans[0], isA<MdText>().having((t) => t.text, 'text', 'Some '));
      expect(
        spans[1],
        isA<MdEmphasis>()
            .having((e) => e.bold, 'bold', true)
            .having(
              (e) => e.children,
              'children',
              [isA<MdText>().having((t) => t.text, 'text', 'bold')],
            ),
      );
    });

    test(
        'an unclosed inline code span renders as code, not a literal '
        'backtick', () {
      final blocks = MarkdownParser.parse('Run `echo hi', streaming: true);
      final spans = (blocks.single as MdParagraph).spans;
      expect(spans, hasLength(2));
      expect(
        spans[1],
        isA<MdCode>().having((c) => c.code, 'code', 'echo hi'),
      );
    });

    test(
        'an unclosed strikethrough span renders as strikethrough, not '
        'literal tildes', () {
      final blocks = MarkdownParser.parse('Old ~~price', streaming: true);
      final spans = (blocks.single as MdParagraph).spans;
      expect(spans, hasLength(2));
      expect(
        spans[1],
        isA<MdEmphasis>()
            .having((e) => e.strikethrough, 'strikethrough', true)
            .having(
              (e) => e.children,
              'children',
              [isA<MdText>().having((t) => t.text, 'text', 'price')],
            ),
      );
    });

    test(
        'a table header with no delimiter row yet is withheld, not shown '
        'as raw pipes', () {
      final blocks = MarkdownParser.parse('| Name | Age |', streaming: true);
      expect(blocks, isEmpty);
    });

    test('the withheld header resolves into a table once the delimiter row '
        'arrives', () {
      final blocks = MarkdownParser.parse(
        '| Name | Age |\n|---|---|',
        streaming: true,
      );
      expect(blocks.whereType<MdTable>(), isNotEmpty);
    });

    testWidgets(
        'a streaming table header with no delimiter row yet does not throw',
        (tester) async {
      const source = '| Name | Age |';
      for (var i = 1; i <= source.length; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                data: source.substring(0, i),
                isStreaming: true,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'threw at length $i');
      }
    });
  });

  group(
      'streaming: false (final) never silently drops ambiguous trailing '
      'syntax', () {
    test('a genuinely unclosed bold span renders literally', () {
      final blocks = MarkdownParser.parse('Some **bold');
      final spans = (blocks.single as MdParagraph).spans;
      expect(
        spans,
        [isA<MdText>().having((t) => t.text, 'text', 'Some **bold')],
      );
    });

    test('a header-shaped line with no delimiter row renders as a plain '
        'paragraph, not nothing', () {
      final blocks = MarkdownParser.parse('| Name | Age |');
      expect(blocks.single, isA<MdParagraph>());
    });
  });

  test(
      'parseIncremental discards a stale streaming cache once streaming '
      'ends, instead of permanently hiding withheld content', () {
    const source = '| Name | Age |';
    final midStream = MarkdownParser.parseIncremental(
      source,
      null,
      streaming: true,
    );
    expect(midStream.blocks, isEmpty);

    final finalResult = MarkdownParser.parseIncremental(
      source,
      midStream,
      streaming: false,
    );
    expect(finalResult.blocks, isNotEmpty);
    expect(
      _canonBlocks(finalResult.blocks),
      equals(_canonBlocks(MarkdownParser.parse(source))),
    );
  });

  test('an incremental resume rebases a nested blockquote child, not just '
      'the quote itself', () {
    // The tail re-parse of `> x\n> y\n> z` produces sourceStarts relative to
    // the tail substring; _shift must rebase the nested paragraph's start
    // along with the quote's own, or the two diverge from a full reparse.
    const stepN = 'a\n\nb\n\n> x\n> y';
    const stepNPlus1 = 'a\n\nb\n\n> x\n> y\n> z';

    final previous = MarkdownParseResult(MarkdownParser.parse(stepN), stepN);
    final incremental = MarkdownParser.parseIncremental(
      stepNPlus1,
      previous,
    );

    expect(
      _canonBlocks(incremental.blocks),
      equals(_canonBlocks(MarkdownParser.parse(stepNPlus1))),
    );
  });
}

// ---------------------------------------------------------------------
// Structural comparison for MdBlock/MdInline trees.
//
// These AST types intentionally don't implement `==` (they're plain parse
// output, not model objects compared elsewhere), so equivalence checks here
// go through a canonical Map/List form and rely on `equals()`'s deep
// collection comparison instead.
// ---------------------------------------------------------------------

List<Object?> _canonBlocks(List<MdBlock> blocks) =>
    blocks.map(_canonBlock).toList();

Object? _canonBlock(MdBlock block) {
  return switch (block) {
    final MdParagraph b => {
        'type': 'paragraph',
        'start': b.sourceStart,
        'spans': b.spans.map(_canonInline).toList(),
      },
    final MdHeading b => {
        'type': 'heading',
        'start': b.sourceStart,
        'level': b.level,
        'spans': b.spans.map(_canonInline).toList(),
      },
    final MdCodeBlock b => {
        'type': 'code_block',
        'start': b.sourceStart,
        'language': b.language,
        'code': b.code,
        'closed': b.closed,
      },
    final MdList b => {
        'type': 'list',
        'start': b.sourceStart,
        'ordered': b.ordered,
        'startNumber': b.start,
        'items': b.items
            .map(
              (item) => {
                'spans': item.spans.map(_canonInline).toList(),
                'depth': item.depth,
                'checked': item.checked,
              },
            )
            .toList(),
      },
    final MdQuote b => {
        'type': 'quote',
        'start': b.sourceStart,
        'children': b.children.map(_canonBlock).toList(),
      },
    final MdRule b => {'type': 'rule', 'start': b.sourceStart},
    final MdTable b => {
        'type': 'table',
        'start': b.sourceStart,
        'header':
            b.header.map((cell) => cell.map(_canonInline).toList()).toList(),
        'rows': b.rows
            .map(
              (row) => row.map((cell) => cell.map(_canonInline).toList())
                  .toList(),
            )
            .toList(),
        'alignments': b.alignments.map((a) => a.name).toList(),
      },
  };
}

Object? _canonInline(MdInline node) {
  return switch (node) {
    final MdText n => {'type': 'text', 'text': n.text},
    final MdEmphasis n => {
        'type': 'emphasis',
        'bold': n.bold,
        'italic': n.italic,
        'strikethrough': n.strikethrough,
        'children': n.children.map(_canonInline).toList(),
      },
    final MdCode n => {'type': 'code', 'code': n.code},
    final MdLink n => {
        'type': 'link',
        'url': n.url,
        'children': n.children.map(_canonInline).toList(),
      },
    final MdImage n => {'type': 'image', 'url': n.url, 'alt': n.alt},
    MdLineBreak _ => {'type': 'break'},
  };
}
