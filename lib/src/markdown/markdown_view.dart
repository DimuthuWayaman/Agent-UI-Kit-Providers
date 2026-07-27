import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/agent_theme.dart';
import '../widgets/code_block.dart';
import 'markdown_ast.dart';
import 'markdown_parser.dart';

/// Renders markdown text as Flutter widgets.
///
/// Built for streaming: the parse result is cached and, when [data] grows by
/// appending, only the final block is re-parsed. Rebuilding on every token is
/// therefore cheap, where a full re-parse per token would be quadratic across
/// a long response.
///
/// Text selection is not handled here — wrap a subtree in a [SelectionArea]
/// to make it selectable. That composes better than per-widget selectability
/// and lets a user drag-select across bubbles.
class MarkdownView extends StatefulWidget {
  /// The markdown source.
  final String data;

  /// Base style for body text. Falls back to the theme's body style.
  final TextStyle? baseStyle;

  /// Color applied to body text. Falls back to the theme's primary text color.
  final Color? textColor;

  /// Called when a link is tapped, with the destination URL.
  ///
  /// The kit takes no URL-launching dependency, so wire this to
  /// `url_launcher` (or your router) in the host app. Links render as plain
  /// styled text when this is null.
  final ValueChanged<String>? onLinkTap;

  /// Called when an image fails to load, for logging.
  final void Function(String url, Object error)? onImageError;

  /// Whether fenced code blocks show their header bar.
  final bool showCodeHeader;

  /// Text alignment for paragraphs.
  final TextAlign textAlign;

  const MarkdownView({
    super.key,
    required this.data,
    this.baseStyle,
    this.textColor,
    this.onLinkTap,
    this.onImageError,
    this.showCodeHeader = true,
    this.textAlign = TextAlign.start,
  });

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  MarkdownParseResult? _cache;

  /// Keyed by URL so recognizers survive rebuilds instead of being recreated
  /// (and leaked) on every streamed token.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TapGestureRecognizer? _recognizerFor(String url) {
    final onTap = widget.onLinkTap;
    if (onTap == null) return null;
    // The callback is reassigned on every call so a changed onLinkTap is
    // honored by recognizers created on an earlier build.
    return _recognizers.putIfAbsent(url, TapGestureRecognizer.new)
      ..onTap = () => onTap(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    _cache = MarkdownParser.parseIncremental(widget.data, _cache);
    final blocks = _cache!.blocks;

    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: theme.spacing.sm),
          _buildBlock(context, blocks[i]),
        ],
      ],
    );
  }

  TextStyle get _effectiveBase {
    final theme = AgentTheme.of(context);
    final base = widget.baseStyle ?? theme.typography.body;
    return base.copyWith(color: widget.textColor ?? theme.colors.textPrimary);
  }

  Widget _buildBlock(BuildContext context, MdBlock block) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    switch (block) {
      case final MdParagraph b:
        return Text.rich(
          TextSpan(children: _inlineSpans(b.spans, _effectiveBase)),
          textAlign: widget.textAlign,
        );

      case final MdHeading b:
        final style = switch (b.level) {
          1 => theme.typography.heading1,
          2 => theme.typography.heading2,
          _ => theme.typography.heading3,
        };
        return Padding(
          padding: EdgeInsets.only(top: theme.spacing.xs),
          child: Text.rich(
            TextSpan(
              children: _inlineSpans(
                b.spans,
                style.copyWith(
                  color: widget.textColor ?? colors.textPrimary,
                ),
              ),
            ),
            textAlign: widget.textAlign,
          ),
        );

      case final MdCodeBlock b:
        return CodeBlock(
          code: b.code,
          language: b.language,
          showHeader: widget.showCodeHeader,
        );

      case MdRule _:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
          child: Divider(height: 1, thickness: 1, color: colors.border),
        );

      case final MdQuote b:
        return Container(
          padding: EdgeInsets.only(left: theme.spacing.md),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colors.accent.withValues(alpha: 0.5), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final child in b.children) _buildBlock(context, child),
            ],
          ),
        );

      case final MdList b:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < b.items.length; i++)
              _buildListItem(context, b, b.items[i], i),
          ],
        );

      case final MdTable b:
        return _buildTable(context, b);
    }
  }

  Widget _buildListItem(
    BuildContext context,
    MdList list,
    MdListItem item,
    int index,
  ) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final base = _effectiveBase;

    Widget leading;
    if (item.checked != null) {
      leading = Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(
          item.checked!
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 16,
          color: item.checked! ? colors.accent : colors.textTertiary,
        ),
      );
    } else if (list.ordered) {
      leading = Text('${list.start + index}.', style: base.copyWith(color: colors.textSecondary));
    } else {
      // Nested levels alternate glyphs so depth is readable without indent
      // guides.
      leading = Text(
        item.depth == 0 ? '•' : '◦',
        style: base.copyWith(color: colors.textSecondary),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: item.depth * theme.spacing.lg,
        bottom: theme.spacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: list.ordered ? 24 : 18,
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: _inlineSpans(item.spans, base))),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, MdTable table) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final base = _effectiveBase;

    Widget cell(List<MdInline> spans, MdAlign align, {bool header = false}) {
      final style = header ? base.copyWith(fontWeight: FontWeight.w600) : base;
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.md,
          vertical: theme.spacing.sm,
        ),
        child: Text.rich(
          TextSpan(children: _inlineSpans(spans, style)),
          textAlign: switch (align) {
            MdAlign.left => TextAlign.left,
            MdAlign.center => TextAlign.center,
            MdAlign.right => TextAlign.right,
          },
        ),
      );
    }

    MdAlign alignAt(int i) =>
        i < table.alignments.length ? table.alignments[i] : MdAlign.left;

    // Table demands that every row have the same number of children. While a
    // table streams in, the row being typed is short — sometimes a single cell
    // against a three-column header — so rows are padded out to the widest
    // row seen. Without this the widget asserts mid-response.
    var columnCount = table.header.length;
    for (final row in table.rows) {
      if (row.length > columnCount) columnCount = row.length;
    }
    if (columnCount == 0) return const SizedBox.shrink();

    List<Widget> cellsFor(List<List<MdInline>> row, {bool header = false}) {
      return List<Widget>.generate(
        columnCount,
        (i) => cell(
          i < row.length ? row[i] : const <MdInline>[],
          alignAt(i),
          header: header,
        ),
      );
    }

    // Tables are the one block that legitimately exceeds the bubble width, so
    // give it its own horizontal scroll rather than squeezing columns.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: theme.radii.smallRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(
            inside: BorderSide(color: colors.border),
          ),
          children: [
            if (table.header.isNotEmpty)
              TableRow(
                decoration: BoxDecoration(color: colors.surfaceContainerHigh),
                children: cellsFor(table.header, header: true),
              ),
            for (final row in table.rows) TableRow(children: cellsFor(row)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Inline
  // -------------------------------------------------------------------

  /// Converts inline nodes to spans.
  ///
  /// [recognizer] is threaded down to the leaf spans rather than set on an
  /// ancestor: hit testing resolves to the deepest span at a position, so a
  /// recognizer on a span that only has `children` is never consulted and the
  /// link would silently do nothing.
  List<InlineSpan> _inlineSpans(
    List<MdInline> nodes,
    TextStyle style, {
    GestureRecognizer? recognizer,
  }) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      switch (node) {
        case final MdText n:
          spans.add(
            TextSpan(
              text: n.text,
              style: style,
              recognizer: recognizer,
              mouseCursor:
                  recognizer != null ? SystemMouseCursors.click : null,
            ),
          );

        case MdLineBreak _:
          spans.add(const TextSpan(text: '\n'));

        case final MdEmphasis n:
          spans.addAll(
            _inlineSpans(
              n.children,
              style.copyWith(
                fontWeight: n.bold ? FontWeight.w700 : null,
                fontStyle: n.italic ? FontStyle.italic : null,
                decoration:
                    n.strikethrough ? TextDecoration.lineThrough : null,
              ),
              recognizer: recognizer,
            ),
          );

        case final MdCode n:
          // WidgetSpan rather than a styled TextSpan so the tinted background
          // gets real padding and rounded corners.
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.inlineCodeSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  n.code,
                  style: theme.typography.inlineCode.copyWith(
                    color: style.color,
                  ),
                ),
              ),
            ),
          );

        case final MdLink n:
          spans.addAll(
            _inlineSpans(
              n.children,
              style.copyWith(
                color: colors.accent,
                decoration: TextDecoration.underline,
                decorationColor: colors.accent.withValues(alpha: 0.4),
              ),
              recognizer: _recognizerFor(n.url),
            ),
          );

        case final MdImage n:
          spans.add(
            WidgetSpan(
              child: _MarkdownImage(
                url: n.url,
                alt: n.alt,
                onError: widget.onImageError,
              ),
            ),
          );
      }
    }

    return spans;
  }
}

class _MarkdownImage extends StatelessWidget {
  final String url;
  final String alt;
  final void Function(String url, Object error)? onError;

  const _MarkdownImage({
    required this.url,
    required this.alt,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.spacing.xs),
      child: ClipRRect(
        borderRadius: theme.radii.smallRadius,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          semanticLabel: alt.isEmpty ? null : alt,
          errorBuilder: (context, error, stack) {
            onError?.call(url, error);
            return Container(
              padding: EdgeInsets.all(theme.spacing.md),
              decoration: BoxDecoration(
                color: theme.colors.surfaceContainerHigh,
                borderRadius: theme.radii.smallRadius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 16,
                    color: theme.colors.textTertiary,
                  ),
                  SizedBox(width: theme.spacing.sm),
                  Text(
                    alt.isEmpty ? 'Image unavailable' : alt,
                    style: theme.typography.caption.copyWith(
                      color: theme.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              height: 80,
              width: 80,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
