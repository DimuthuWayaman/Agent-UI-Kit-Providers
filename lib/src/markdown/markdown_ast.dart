import 'package:flutter/foundation.dart';

/// Inline-level markdown nodes.
@immutable
sealed class MdInline {
  const MdInline();
}

/// A run of literal text.
class MdText extends MdInline {
  /// The literal characters.
  final String text;

  const MdText(this.text);
}

/// Text carrying one or more emphasis styles.
class MdEmphasis extends MdInline {
  /// Nested inline content.
  final List<MdInline> children;

  /// Rendered with a heavier font weight.
  final bool bold;

  /// Rendered italicised.
  final bool italic;

  /// Rendered with a line through it.
  final bool strikethrough;

  const MdEmphasis(
    this.children, {
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
  });
}

/// An inline `code` span.
class MdCode extends MdInline {
  /// The code text, with delimiters removed.
  final String code;

  const MdCode(this.code);
}

/// A hyperlink.
class MdLink extends MdInline {
  /// Inline content forming the link label.
  final List<MdInline> children;

  /// Destination URL.
  final String url;

  const MdLink(this.children, this.url);
}

/// An inline image reference.
class MdImage extends MdInline {
  /// Alternative text.
  final String alt;

  /// Image URL.
  final String url;

  const MdImage(this.alt, this.url);
}

/// An explicit line break inside a paragraph.
class MdLineBreak extends MdInline {
  const MdLineBreak();
}

/// Block-level markdown nodes.
///
/// Every block records [sourceStart], the offset in the original document
/// where it begins. The streaming parser uses it to re-parse only the final
/// block when new tokens arrive instead of the whole document.
@immutable
sealed class MdBlock {
  /// Offset into the source string where this block starts.
  final int sourceStart;

  const MdBlock(this.sourceStart);
}

/// A paragraph of inline content.
class MdParagraph extends MdBlock {
  /// The paragraph's inline content.
  final List<MdInline> spans;

  const MdParagraph(this.spans, super.sourceStart);
}

/// An ATX (`#`) or setext (`===`) heading.
class MdHeading extends MdBlock {
  /// Heading level, 1 through 6.
  final int level;

  /// The heading's inline content.
  final List<MdInline> spans;

  const MdHeading(this.level, this.spans, super.sourceStart);
}

/// A fenced or indented code block.
class MdCodeBlock extends MdBlock {
  /// Info string after the opening fence, e.g. `dart`.
  final String? language;

  /// Raw code contents.
  final String code;

  /// Whether the closing fence has been seen.
  ///
  /// False while a fence is still streaming in, which lets the renderer show
  /// the block without waiting for the terminator.
  final bool closed;

  const MdCodeBlock(this.language, this.code, this.closed, super.sourceStart);
}

/// A single entry in an [MdList].
@immutable
class MdListItem {
  /// The item's inline content.
  final List<MdInline> spans;

  /// Nesting depth, starting at 0.
  final int depth;

  /// Checkbox state for task list items, or `null` for ordinary items.
  final bool? checked;

  const MdListItem(this.spans, this.depth, {this.checked});
}

/// A bulleted or numbered list.
class MdList extends MdBlock {
  /// Whether the list is numbered.
  final bool ordered;

  /// First number for ordered lists.
  final int start;

  /// The list's entries.
  final List<MdListItem> items;

  const MdList(
    this.ordered,
    this.start,
    this.items,
    super.sourceStart,
  );
}

/// A `>` blockquote containing nested blocks.
class MdQuote extends MdBlock {
  /// Blocks nested inside the quote.
  final List<MdBlock> children;

  const MdQuote(this.children, super.sourceStart);
}

/// A thematic break (`---`).
class MdRule extends MdBlock {
  const MdRule(super.sourceStart);
}

/// Column alignment within an [MdTable].
enum MdAlign {
  /// Default, left-aligned in LTR.
  left,

  /// Centered.
  center,

  /// Right-aligned.
  right,
}

/// A pipe table.
class MdTable extends MdBlock {
  /// Header cells, empty when the table has no header row.
  final List<List<MdInline>> header;

  /// Body rows, each a list of cells.
  final List<List<List<MdInline>>> rows;

  /// Per-column alignment.
  final List<MdAlign> alignments;

  const MdTable(
    this.header,
    this.rows,
    this.alignments,
    super.sourceStart,
  );
}
