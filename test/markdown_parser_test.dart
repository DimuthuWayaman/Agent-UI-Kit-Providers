import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flattens inline nodes back to plain text so assertions stay readable.
String flatten(List<MdInline> nodes) {
  final buffer = StringBuffer();
  for (final node in nodes) {
    switch (node) {
      case final MdText n:
        buffer.write(n.text);
      case final MdCode n:
        buffer.write(n.code);
      case final MdEmphasis n:
        buffer.write(flatten(n.children));
      case final MdLink n:
        buffer.write(flatten(n.children));
      case final MdImage n:
        buffer.write(n.alt);
      case MdLineBreak _:
        buffer.write('\n');
    }
  }
  return buffer.toString();
}

void main() {
  group('block parsing', () {
    test('parses a paragraph', () {
      final blocks = MarkdownParser.parse('Hello world');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<MdParagraph>());
      expect(flatten((blocks.first as MdParagraph).spans), 'Hello world');
    });

    test('parses ATX headings at each level', () {
      final blocks = MarkdownParser.parse('# One\n\n### Three');
      expect(blocks, hasLength(2));
      expect((blocks[0] as MdHeading).level, 1);
      expect((blocks[1] as MdHeading).level, 3);
    });

    test('strips decorative trailing hashes from headings', () {
      final blocks = MarkdownParser.parse('## Title ##');
      expect(flatten((blocks.first as MdHeading).spans), 'Title');
    });

    test('parses a setext heading', () {
      final blocks = MarkdownParser.parse('Title\n=====');
      expect(blocks.first, isA<MdHeading>());
      expect((blocks.first as MdHeading).level, 1);
    });

    test('parses a fenced code block with a language', () {
      final blocks = MarkdownParser.parse('```dart\nvar x = 1;\n```');
      final code = blocks.first as MdCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'var x = 1;');
      expect(code.closed, isTrue);
    });

    test('marks an unterminated fence as open so it can render while '
        'streaming', () {
      final blocks = MarkdownParser.parse('```dart\nvar x = 1;');
      final code = blocks.first as MdCodeBlock;
      expect(code.closed, isFalse);
      expect(code.code, 'var x = 1;');
    });

    test('does not treat markdown inside a code fence as markup', () {
      final blocks = MarkdownParser.parse('```\n# not a heading\n```');
      expect(blocks.single, isA<MdCodeBlock>());
      expect((blocks.single as MdCodeBlock).code, '# not a heading');
    });

    test('parses bullet and ordered lists', () {
      final bullets = MarkdownParser.parse('- a\n- b');
      expect((bullets.first as MdList).ordered, isFalse);
      expect((bullets.first as MdList).items, hasLength(2));

      final ordered = MarkdownParser.parse('1. a\n2. b');
      expect((ordered.first as MdList).ordered, isTrue);
      expect((ordered.first as MdList).start, 1);
    });

    test('parses task list checkboxes', () {
      final blocks = MarkdownParser.parse('- [ ] todo\n- [x] done');
      final list = blocks.first as MdList;
      expect(list.items[0].checked, isFalse);
      expect(list.items[1].checked, isTrue);
      expect(flatten(list.items[1].spans), 'done');
    });

    test('tracks nesting depth from indentation', () {
      final blocks = MarkdownParser.parse('- top\n  - nested');
      final list = blocks.first as MdList;
      expect(list.items[0].depth, 0);
      expect(list.items[1].depth, 1);
    });

    test('parses a blockquote containing blocks', () {
      final blocks = MarkdownParser.parse('> quoted text');
      final quote = blocks.first as MdQuote;
      expect(quote.children.first, isA<MdParagraph>());
    });

    test('parses thematic breaks', () {
      expect(MarkdownParser.parse('---').single, isA<MdRule>());
      expect(MarkdownParser.parse('***').single, isA<MdRule>());
    });

    test('parses a table with alignments', () {
      final blocks = MarkdownParser.parse(
        '| a | b |\n|:--|--:|\n| 1 | 2 |',
      );
      final table = blocks.first as MdTable;
      expect(table.header, hasLength(2));
      expect(table.rows, hasLength(1));
      expect(table.alignments, [MdAlign.left, MdAlign.right]);
    });
  });

  group('inline parsing', () {
    test('parses bold, italic and strikethrough', () {
      final bold = MarkdownParser.parseInline('**b**').single as MdEmphasis;
      expect(bold.bold, isTrue);

      final italic = MarkdownParser.parseInline('*i*').single as MdEmphasis;
      expect(italic.italic, isTrue);

      final strike =
          MarkdownParser.parseInline('~~s~~').single as MdEmphasis;
      expect(strike.strikethrough, isTrue);
    });

    test('parses inline code', () {
      final nodes = MarkdownParser.parseInline('use `flutter run` now');
      expect(nodes.whereType<MdCode>().single.code, 'flutter run');
    });

    test('does not read emphasis markers inside inline code', () {
      final nodes = MarkdownParser.parseInline('`a * b`');
      expect(nodes.whereType<MdCode>().single.code, 'a * b');
      expect(nodes.whereType<MdEmphasis>(), isEmpty);
    });

    test('treats underscores inside words as literal', () {
      final nodes = MarkdownParser.parseInline('my_var_name');
      expect(nodes.whereType<MdEmphasis>(), isEmpty);
      expect(flatten(nodes), 'my_var_name');
    });

    test('parses links and images', () {
      final link = MarkdownParser.parseInline('[x](https://a.com)')
          .whereType<MdLink>()
          .single;
      expect(link.url, 'https://a.com');

      final image = MarkdownParser.parseInline('![alt](https://a.com/i.png)')
          .whereType<MdImage>()
          .single;
      expect(image.alt, 'alt');
    });

    test('autolinks bare URLs without swallowing trailing punctuation', () {
      final link = MarkdownParser.parseInline('see https://a.com.')
          .whereType<MdLink>()
          .single;
      expect(link.url, 'https://a.com');
    });

    test('honors backslash escapes', () {
      final nodes = MarkdownParser.parseInline(r'\*not italic\*');
      expect(nodes.whereType<MdEmphasis>(), isEmpty);
      expect(flatten(nodes), '*not italic*');
    });

    test('leaves an unmatched delimiter as literal text', () {
      final nodes = MarkdownParser.parseInline('2 * 3 = 6');
      expect(nodes.whereType<MdEmphasis>(), isEmpty);
      expect(flatten(nodes), '2 * 3 = 6');
    });
  });

  group('incremental parsing', () {
    test('produces the same result as a full parse as text streams in', () {
      const full = '# Title\n\nSome **text**.\n\n- a\n- b\n\n```dart\nx;\n```';

      MarkdownParseResult? cache;
      for (var i = 1; i <= full.length; i++) {
        cache = MarkdownParser.parseIncremental(full.substring(0, i), cache);
      }

      final incremental = cache!.blocks;
      final oneShot = MarkdownParser.parse(full);

      expect(incremental.length, oneShot.length);
      for (var i = 0; i < oneShot.length; i++) {
        expect(incremental[i].runtimeType, oneShot[i].runtimeType);
        expect(
          incremental[i].sourceStart,
          oneShot[i].sourceStart,
          reason: 'block $i offset must match a full parse',
        );
      }
    });

    test('reparses from scratch when the new text is not a prefix extension',
        () {
      final first = MarkdownParser.parseIncremental('hello', null);
      final second = MarkdownParser.parseIncremental('different', first);
      expect(flatten((second.blocks.single as MdParagraph).spans), 'different');
    });

    test('returns the cached result unchanged when text has not grown', () {
      final first = MarkdownParser.parseIncremental('hello', null);
      final second = MarkdownParser.parseIncremental('hello', first);
      expect(identical(first, second), isTrue);
    });

    test('merges a new list item into the preceding list', () {
      // Regression: a half-typed "-" parses as a paragraph, so the space that
      // turns it into a list item changes the second-to-last block. Resuming
      // from only the last block left two adjacent MdLists behind.
      var cache = MarkdownParser.parseIncremental('- a\n-', null);
      expect(cache.blocks, hasLength(2));

      cache = MarkdownParser.parseIncremental('- a\n- ', cache);
      expect(cache.blocks, hasLength(1));
      expect(cache.blocks.single, isA<MdList>());

      cache = MarkdownParser.parseIncremental('- a\n- b', cache);
      expect((cache.blocks.single as MdList).items, hasLength(2));
    });

    test('promotes a paragraph to a heading when a setext underline arrives',
        () {
      var cache = MarkdownParser.parseIncremental('Title', null);
      expect(cache.blocks.single, isA<MdParagraph>());

      cache = MarkdownParser.parseIncremental('Title\n===', cache);
      expect(cache.blocks.single, isA<MdHeading>());
    });
  });
}
