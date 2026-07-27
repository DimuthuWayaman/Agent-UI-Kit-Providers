import 'package:flutter/foundation.dart';

import 'markdown_ast.dart';

/// The parsed form of a document, plus the source it came from.
///
/// Feed the previous result back into [MarkdownParser.parseIncremental] to
/// reuse work across streaming updates.
@immutable
class MarkdownParseResult {
  /// Block-level nodes, in document order.
  final List<MdBlock> blocks;

  /// The exact source string these blocks were produced from.
  final String source;

  const MarkdownParseResult(this.blocks, this.source);
}

/// A small, dependency-free markdown parser covering the subset that language
/// models actually emit.
///
/// Supported: ATX and setext headings, paragraphs, fenced and indented code,
/// bullet/ordered/task lists, blockquotes, thematic breaks, pipe tables, and
/// inline emphasis, code, links, images and autolinks.
///
/// Deliberately not supported: reference links, footnotes, raw HTML. Those
/// are rare in chat output and each adds parser surface that has to stay
/// correct while text is half-streamed.
class MarkdownParser {
  const MarkdownParser._();

  /// Parses [source] from scratch.
  static List<MdBlock> parse(String source) {
    final lines = _splitLines(source);
    return _parseBlocks(lines, 0, lines.length);
  }

  /// Parses [source], reusing [previous] when it is a prefix of the new text.
  ///
  /// Streaming appends one chunk at a time, so re-parsing the whole document
  /// per chunk costs O(n²) over a response. Instead the parse resumes from the
  /// **second-to-last** block and everything before that is reused.
  ///
  /// One block of slack is required, not zero. A half-typed `-` parses as a
  /// paragraph; when the following space arrives it becomes a list item that
  /// merges into the list *before* it, so an append can change the
  /// second-to-last block and not just the last one. The effect cannot cascade
  /// further back — two adjacent lists would already have been parsed as one —
  /// so one block of slack is also sufficient.
  static MarkdownParseResult parseIncremental(
    String source,
    MarkdownParseResult? previous,
  ) {
    if (previous == null ||
        previous.blocks.isEmpty ||
        !source.startsWith(previous.source)) {
      return MarkdownParseResult(parse(source), source);
    }
    if (source.length == previous.source.length) return previous;

    final resumeIndex =
        previous.blocks.length >= 2 ? previous.blocks.length - 2 : 0;
    final resumeAt = previous.blocks[resumeIndex].sourceStart;
    final stable = previous.blocks.take(resumeIndex).toList();

    final tail = source.substring(resumeAt);
    final tailBlocks = parse(tail);

    // Blocks from the tail carry offsets relative to it; shift them back into
    // document coordinates so a later incremental pass resumes correctly.
    for (final block in tailBlocks) {
      stable.add(_shift(block, resumeAt));
    }
    return MarkdownParseResult(stable, source);
  }

  static MdBlock _shift(MdBlock block, int delta) {
    final at = block.sourceStart + delta;
    return switch (block) {
      final MdParagraph b => MdParagraph(b.spans, at),
      final MdHeading b => MdHeading(b.level, b.spans, at),
      final MdCodeBlock b => MdCodeBlock(b.language, b.code, b.closed, at),
      final MdList b => MdList(b.ordered, b.start, b.items, at),
      final MdQuote b => MdQuote(b.children, at),
      MdRule _ => MdRule(at),
      final MdTable b => MdTable(b.header, b.rows, b.alignments, at),
    };
  }

  // -------------------------------------------------------------------
  // Block level
  // -------------------------------------------------------------------

  static List<_Line> _splitLines(String source) {
    final lines = <_Line>[];
    var start = 0;
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        var end = i;
        if (end > start && source.codeUnitAt(end - 1) == 0x0D) end--;
        lines.add(_Line(source.substring(start, end), start));
        start = i + 1;
      }
    }
    if (start <= source.length) {
      lines.add(_Line(source.substring(start), start));
    }
    return lines;
  }

  static List<MdBlock> _parseBlocks(List<_Line> lines, int from, int to) {
    final blocks = <MdBlock>[];
    var i = from;

    while (i < to) {
      final line = lines[i];
      final trimmed = line.text.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced code block.
      final fence = _fenceMarker(trimmed);
      if (fence != null) {
        final language = trimmed.substring(fence.length).trim();
        final buffer = <String>[];
        var closed = false;
        var j = i + 1;
        for (; j < to; j++) {
          final candidate = lines[j].text.trim();
          if (candidate.startsWith(fence) &&
              candidate.replaceAll(fence, '').trim().isEmpty) {
            closed = true;
            break;
          }
          buffer.add(lines[j].text);
        }
        blocks.add(
          MdCodeBlock(
            language.isEmpty ? null : language,
            buffer.join('\n'),
            closed,
            line.start,
          ),
        );
        i = closed ? j + 1 : j;
        continue;
      }

      // Thematic break.
      if (_isRule(trimmed)) {
        blocks.add(MdRule(line.start));
        i++;
        continue;
      }

      // ATX heading.
      final heading = _atxHeading(trimmed);
      if (heading != null) {
        blocks.add(
          MdHeading(heading.$1, parseInline(heading.$2), line.start),
        );
        i++;
        continue;
      }

      // Blockquote: gather the contiguous run, strip markers, recurse.
      if (trimmed.startsWith('>')) {
        final inner = <_Line>[];
        var j = i;
        for (; j < to; j++) {
          final t = lines[j].text.trimLeft();
          if (!t.startsWith('>')) {
            if (t.isEmpty) break;
            // Lazy continuation: a plain line continues the quote.
            inner.add(lines[j]);
            continue;
          }
          var content = t.substring(1);
          if (content.startsWith(' ')) content = content.substring(1);
          inner.add(_Line(content, lines[j].start));
        }
        blocks.add(MdQuote(_parseBlocks(inner, 0, inner.length), line.start));
        i = j;
        continue;
      }

      // Pipe table: needs a delimiter row directly beneath the header.
      if (line.text.contains('|') &&
          i + 1 < to &&
          _isTableDelimiter(lines[i + 1].text)) {
        final alignments = _parseAlignments(lines[i + 1].text);
        final header = _splitRow(line.text).map(parseInline).toList();
        final rows = <List<List<MdInline>>>[];
        var j = i + 2;
        for (; j < to; j++) {
          final t = lines[j].text.trim();
          if (t.isEmpty || !t.contains('|')) break;
          rows.add(_splitRow(lines[j].text).map(parseInline).toList());
        }
        blocks.add(MdTable(header, rows, alignments, line.start));
        i = j;
        continue;
      }

      // Lists.
      if (_listMarker(line.text) != null) {
        final items = <MdListItem>[];
        final firstMarker = _listMarker(line.text)!;
        final ordered = firstMarker.ordered;
        var j = i;
        for (; j < to; j++) {
          final marker = _listMarker(lines[j].text);
          if (marker == null) {
            final t = lines[j].text.trim();
            // Blank line ends the list; an indented line continues the
            // previous item's text.
            if (t.isEmpty) break;
            if (lines[j].text.startsWith('  ') && items.isNotEmpty) {
              final last = items.removeLast();
              items.add(
                MdListItem(
                  [...last.spans, const MdText(' '), ...parseInline(t)],
                  last.depth,
                  checked: last.checked,
                ),
              );
              continue;
            }
            break;
          }
          if (marker.ordered != ordered) break;
          items.add(
            MdListItem(
              parseInline(marker.content),
              marker.depth,
              checked: marker.checked,
            ),
          );
        }
        blocks.add(MdList(ordered, firstMarker.number ?? 1, items, line.start));
        i = j;
        continue;
      }

      // Paragraph: run until a blank line or the start of another block.
      final buffer = <String>[];
      var j = i;
      var level = 0;
      for (; j < to; j++) {
        final t = lines[j].text.trim();
        if (t.isEmpty) break;
        if (j > i) {
          // Setext underline promotes the paragraph collected so far.
          if (_isSetext(t)) {
            level = t.startsWith('=') ? 1 : 2;
            j++;
            break;
          }
          if (_fenceMarker(t) != null ||
              _atxHeading(t) != null ||
              _isRule(t) ||
              t.startsWith('>') ||
              _listMarker(lines[j].text) != null) {
            break;
          }
        }
        buffer.add(t);
      }
      final text = buffer.join('\n');
      blocks.add(
        level > 0
            ? MdHeading(level, parseInline(text), line.start)
            : MdParagraph(parseInline(text), line.start),
      );
      i = j;
    }

    return blocks;
  }

  static String? _fenceMarker(String trimmed) {
    if (trimmed.startsWith('```')) return '```';
    if (trimmed.startsWith('~~~')) return '~~~';
    return null;
  }

  static bool _isRule(String t) {
    if (t.length < 3) return false;
    final c = t[0];
    if (c != '-' && c != '*' && c != '_') return false;
    return t.split('').every((ch) => ch == c || ch == ' ') &&
        t.replaceAll(' ', '').length >= 3;
  }

  static bool _isSetext(String t) {
    if (t.length < 2) return false;
    return t.split('').every((c) => c == '=') ||
        t.split('').every((c) => c == '-');
  }

  static (int, String)? _atxHeading(String t) {
    var level = 0;
    while (level < t.length && t[level] == '#') {
      level++;
    }
    if (level == 0 || level > 6) return null;
    if (level >= t.length) return (level, '');
    if (t[level] != ' ') return null;
    // Trailing hashes are decorative: `## Title ##`.
    var content = t.substring(level + 1).trim();
    while (content.endsWith('#')) {
      content = content.substring(0, content.length - 1).trimRight();
    }
    return (level, content);
  }

  static bool _isTableDelimiter(String line) {
    final t = line.trim();
    if (!t.contains('-') || !t.contains('|')) return false;
    return RegExp(r'^\|?[\s:|-]+\|?$').hasMatch(t) &&
        RegExp(r'-{1,}').hasMatch(t);
  }

  static List<MdAlign> _parseAlignments(String line) {
    return _splitRow(line).map((cell) {
      final c = cell.trim();
      final left = c.startsWith(':');
      final right = c.endsWith(':');
      if (left && right) return MdAlign.center;
      if (right) return MdAlign.right;
      return MdAlign.left;
    }).toList();
  }

  static List<String> _splitRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    final cells = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == r'\' && i + 1 < t.length && t[i + 1] == '|') {
        buffer.write('|');
        i++;
        continue;
      }
      if (c == '|') {
        cells.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(c);
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  static _Marker? _listMarker(String raw) {
    var indent = 0;
    while (indent < raw.length && raw[indent] == ' ') {
      indent++;
    }
    final t = raw.substring(indent);
    if (t.isEmpty) return null;
    final depth = indent ~/ 2;

    // Bullet: -, *, + followed by a space.
    if ((t[0] == '-' || t[0] == '*' || t[0] == '+') &&
        t.length > 1 &&
        t[1] == ' ') {
      var content = t.substring(2);
      bool? checked;
      // Task list: `- [ ] todo` / `- [x] done`.
      if (content.startsWith('[ ] ')) {
        checked = false;
        content = content.substring(4);
      } else if (content.startsWith('[x] ') || content.startsWith('[X] ')) {
        checked = true;
        content = content.substring(4);
      }
      return _Marker(false, depth, content.trim(), null, checked);
    }

    // Ordered: digits followed by . or ) and a space.
    var d = 0;
    while (d < t.length && _isDigit(t.codeUnitAt(d))) {
      d++;
    }
    if (d > 0 &&
        d + 1 < t.length &&
        (t[d] == '.' || t[d] == ')') &&
        t[d + 1] == ' ') {
      return _Marker(
        true,
        depth,
        t.substring(d + 2).trim(),
        int.tryParse(t.substring(0, d)),
        null,
      );
    }
    return null;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  // -------------------------------------------------------------------
  // Inline level
  // -------------------------------------------------------------------

  /// Parses inline markdown within a single block's text.
  static List<MdInline> parseInline(String text) {
    final out = <MdInline>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        out.add(MdText(buffer.toString()));
        buffer.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      final c = text[i];

      // Backslash escape.
      if (c == r'\' && i + 1 < text.length) {
        buffer.write(text[i + 1]);
        i += 2;
        continue;
      }

      if (c == '\n') {
        flush();
        out.add(const MdLineBreak());
        i++;
        continue;
      }

      // Inline code: match the longest backtick run.
      if (c == '`') {
        var run = 0;
        while (i + run < text.length && text[i + run] == '`') {
          run++;
        }
        final delimiter = '`' * run;
        final close = text.indexOf(delimiter, i + run);
        if (close > 0) {
          flush();
          out.add(MdCode(text.substring(i + run, close).trim()));
          i = close + run;
          continue;
        }
      }

      // Image.
      if (c == '!' && i + 1 < text.length && text[i + 1] == '[') {
        final parsed = _parseLink(text, i + 1);
        if (parsed != null) {
          flush();
          out.add(MdImage(parsed.$1, parsed.$2));
          i = parsed.$3;
          continue;
        }
      }

      // Link.
      if (c == '[') {
        final parsed = _parseLink(text, i);
        if (parsed != null) {
          flush();
          out.add(MdLink(parseInline(parsed.$1), parsed.$2));
          i = parsed.$3;
          continue;
        }
      }

      // Strikethrough.
      if (c == '~' && i + 1 < text.length && text[i + 1] == '~') {
        final close = text.indexOf('~~', i + 2);
        if (close > 0) {
          flush();
          out.add(
            MdEmphasis(
              parseInline(text.substring(i + 2, close)),
              strikethrough: true,
            ),
          );
          i = close + 2;
          continue;
        }
      }

      // Bold then italic. Longer delimiter first so `**x**` is not read as
      // two italics.
      if (c == '*' || c == '_') {
        final double = i + 1 < text.length && text[i + 1] == c;
        final delimiter = double ? c * 2 : c;
        // `_` inside a word is a literal underscore (snake_case), not
        // emphasis. `*` has no such restriction.
        final validOpen = c == '*' || i == 0 || !_isWordChar(text[i - 1]);
        if (validOpen) {
          final close = _findClosing(text, i + delimiter.length, delimiter, c);
          if (close > 0) {
            flush();
            final inner = parseInline(
              text.substring(i + delimiter.length, close),
            );
            out.add(
              MdEmphasis(inner, bold: double, italic: !double),
            );
            i = close + delimiter.length;
            continue;
          }
        }
      }

      // Bare URL autolink.
      if ((c == 'h' || c == 'w') && _looksLikeUrlStart(text, i)) {
        final end = _urlEnd(text, i);
        if (end > i) {
          flush();
          final raw = text.substring(i, end);
          final url = raw.startsWith('www.') ? 'https://$raw' : raw;
          out.add(MdLink([MdText(raw)], url));
          i = end;
          continue;
        }
      }

      buffer.write(c);
      i++;
    }

    flush();
    return out;
  }

  static bool _isWordChar(String c) =>
      RegExp(r'[A-Za-z0-9]').hasMatch(c);

  /// Finds the closing delimiter, skipping any inside inline code spans.
  static int _findClosing(
    String text,
    int from,
    String delimiter,
    String marker,
  ) {
    var i = from;
    while (i < text.length) {
      if (text[i] == r'\') {
        i += 2;
        continue;
      }
      if (text[i] == '`') {
        final close = text.indexOf('`', i + 1);
        if (close < 0) return -1;
        i = close + 1;
        continue;
      }
      if (text.startsWith(delimiter, i)) {
        // Reject empty spans like `**`.
        if (i == from) return -1;
        if (marker == '_' &&
            i + delimiter.length < text.length &&
            _isWordChar(text[i + delimiter.length])) {
          i++;
          continue;
        }
        return i;
      }
      i++;
    }
    return -1;
  }

  /// Parses `[label](url)` starting at [start]; returns label, url and the
  /// index just past the closing paren.
  static (String, String, int)? _parseLink(String text, int start) {
    var depth = 0;
    var i = start;
    for (; i < text.length; i++) {
      if (text[i] == r'\') {
        i++;
        continue;
      }
      if (text[i] == '[') depth++;
      if (text[i] == ']') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (i >= text.length || depth != 0) return null;
    final label = text.substring(start + 1, i);
    if (i + 1 >= text.length || text[i + 1] != '(') return null;

    var parenDepth = 0;
    var j = i + 1;
    for (; j < text.length; j++) {
      if (text[j] == '(') parenDepth++;
      if (text[j] == ')') {
        parenDepth--;
        if (parenDepth == 0) break;
      }
    }
    if (j >= text.length) return null;
    var url = text.substring(i + 2, j).trim();
    // Strip an optional title: [x](url "title")
    final space = url.indexOf(' ');
    if (space > 0) url = url.substring(0, space);
    return (label, url, j + 1);
  }

  static bool _looksLikeUrlStart(String text, int i) {
    return text.startsWith('http://', i) ||
        text.startsWith('https://', i) ||
        text.startsWith('www.', i);
  }

  static int _urlEnd(String text, int start) {
    var i = start;
    while (i < text.length && !_isUrlTerminator(text[i])) {
      i++;
    }
    // Trailing punctuation usually belongs to the sentence, not the URL.
    while (i > start && '.,;:!?)]}'.contains(text[i - 1])) {
      i--;
    }
    return i;
  }

  static bool _isUrlTerminator(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '<' || c == '>' || c == '"';
}

class _Line {
  final String text;
  final int start;
  const _Line(this.text, this.start);
}

class _Marker {
  final bool ordered;
  final int depth;
  final String content;
  final int? number;
  final bool? checked;
  const _Marker(
    this.ordered,
    this.depth,
    this.content,
    this.number,
    this.checked,
  );
}
