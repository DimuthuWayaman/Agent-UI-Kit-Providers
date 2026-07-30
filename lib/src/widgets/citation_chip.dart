import 'package:flutter/material.dart';

import '../models/citation.dart';
import '../theme/agent_theme.dart';

/// A compact source reference shown beneath an assistant message.
///
/// Displays a numeric marker and the source host, which is the pattern
/// used by search-grounded assistants: dense enough to sit inline, specific
/// enough to be worth tapping.
class CitationChip extends StatelessWidget {
  /// The source being referenced.
  final Citation citation;

  /// 1-based number shown in the leading marker. Hidden when null.
  final int? index;

  /// Called when the chip is tapped.
  final VoidCallback? onTap;

  const CitationChip({
    super.key,
    required this.citation,
    this.index,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Semantics(
      button: onTap != null,
      label: 'Source: ${citation.title}',
      child: Tooltip(
        message: citation.snippet ?? citation.title,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.xs,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index != null) ...[
                  Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accentSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$index',
                      style: theme.typography.caption.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                  SizedBox(width: theme.spacing.xs),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    citation.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A wrapping row of [CitationChip]s with an optional "Sources" label.
class CitationList extends StatelessWidget {
  /// Sources to display.
  final List<Citation> citations;

  /// Called with the index of a tapped citation.
  final ValueChanged<int>? onTap;

  /// Whether to show the leading "Sources" caption.
  final bool showLabel;

  const CitationList({
    super.key,
    required this.citations,
    this.onTap,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();
    final theme = AgentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel)
          Padding(
            padding: EdgeInsets.only(bottom: theme.spacing.xs),
            child: Text(
              'SOURCES',
              style: theme.typography.overline
                  .copyWith(color: theme.colors.textTertiary),
            ),
          ),
        Wrap(
          spacing: theme.spacing.xs,
          runSpacing: theme.spacing.xs,
          children: [
            for (var i = 0; i < citations.length; i++)
              CitationChip(
                citation: citations[i],
                index: i + 1,
                onTap: onTap == null ? null : () => onTap!(i),
              ),
          ],
        ),
      ],
    );
  }
}
