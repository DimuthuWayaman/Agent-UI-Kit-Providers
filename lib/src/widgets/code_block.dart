import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/syntax_highlighter.dart';
import '../theme/agent_theme.dart';

/// A fenced code block with a language label, copy button and syntax
/// highlighting.
///
/// Long lines scroll horizontally rather than wrapping, because wrapped code
/// is much harder to scan — and very tall blocks collapse behind a
/// "Show more" control so a single long snippet cannot bury the rest of the
/// conversation.
class CodeBlock extends StatefulWidget {
  /// The code to display.
  final String code;

  /// Fence info string (`dart`, `python`, ...). Drives highlighting and the
  /// header label.
  final String? language;

  /// Whether to show the header bar with the language and copy button.
  final bool showHeader;

  /// Whether to show a gutter of line numbers.
  final bool showLineNumbers;

  /// Collapse the block behind a "Show more" control past this height.
  ///
  /// Set to `null` to always render at full height.
  final double? collapsedMaxHeight;

  /// Called after the code is copied, for showing a snackbar or toast.
  final VoidCallback? onCopied;

  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.showHeader = true,
    this.showLineNumbers = false,
    this.collapsedMaxHeight = 320,
    this.onCopied,
  });

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  bool _expanded = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    widget.onCopied?.call();
    // Revert the checkmark after a beat so the button reads as reusable.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final motion = AgentTheme.motionOf(context);
    final colors = theme.colors;

    final spans = SyntaxHighlighter.highlight(
      widget.code,
      widget.language,
      colors.syntax,
      theme.typography.code,
    );

    final lineCount = '\n'.allMatches(widget.code).length + 1;

    // Code scrolls horizontally instead of wrapping, so every line occupies
    // exactly one line box and the full height is known without laying out.
    // Only offer the toggle when the content genuinely exceeds the cap —
    // otherwise a short snippet gets a "Show more" that changes nothing and
    // then reads as "Show less", which looks like the button is inverted.
    final codeStyle = theme.typography.code;
    final lineHeight = MediaQuery.textScalerOf(context)
            .scale(codeStyle.fontSize ?? 12.5) *
        (codeStyle.height ?? 1.5);
    final contentHeight = lineCount * lineHeight + theme.spacing.md * 2;
    final maxHeight = widget.collapsedMaxHeight;
    final overflows = maxHeight != null && contentHeight > maxHeight;

    Widget content = Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.all(theme.spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showLineNumbers) ...[
              _LineNumbers(
                count: lineCount,
                style: theme.typography.code.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              SizedBox(width: theme.spacing.md),
            ],
            SelectableText.rich(
              TextSpan(children: spans),
              style: theme.typography.code,
            ),
          ],
        ),
      ),
    );

    if (overflows && !_expanded) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRect(child: content),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: theme.spacing.sm),
      decoration: BoxDecoration(
        color: colors.codeSurface,
        borderRadius: theme.radii.mediumRadius,
        border: Border.all(color: colors.codeBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader)
            _Header(
              language: widget.language,
              copied: _copied,
              onCopy: _copy,
              duration: motion.fast,
            ),
          Flexible(child: content),
          if (overflows)
            _ExpandToggle(
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String? language;
  final bool copied;
  final VoidCallback onCopy;
  final Duration duration;

  const _Header({
    required this.language,
    required this.copied,
    required this.onCopy,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Container(
      padding: EdgeInsets.fromLTRB(theme.spacing.md, 0, theme.spacing.xs, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.codeBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              language?.toUpperCase() ?? 'CODE',
              style: theme.typography.overline.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: copied ? 'Code copied' : 'Copy code',
            child: TextButton.icon(
              onPressed: onCopy,
              style: TextButton.styleFrom(
                foregroundColor:
                    copied ? colors.success : colors.textSecondary,
                padding: EdgeInsets.symmetric(horizontal: theme.spacing.sm),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.typography.caption,
              ),
              icon: AnimatedSwitcher(
                duration: duration,
                child: Icon(
                  copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(copied),
                  size: 14,
                ),
              ),
              label: Text(copied ? 'Copied' : 'Copy'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNumbers extends StatelessWidget {
  final int count;
  final TextStyle style;

  const _LineNumbers({required this.count, required this.style});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= count; i++) Text('$i', style: style),
      ],
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;

  const _ExpandToggle({required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return InkWell(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.codeBorder)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? 'Show less' : 'Show more',
              style: theme.typography.caption.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: theme.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
