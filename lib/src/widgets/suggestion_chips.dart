import 'package:flutter/material.dart';

import '../theme/agent_theme.dart';

/// A tappable conversation starter or follow-up suggestion.
@immutable
class Suggestion {
  /// Text shown on the chip and, by default, sent when tapped.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Text actually sent when tapped, when it should differ from [label].
  final String? value;

  const Suggestion(this.label, {this.icon, this.value});

  /// The text to send when this suggestion is chosen.
  String get effectiveValue => value ?? label;
}

/// A row or wrap of suggestion chips.
///
/// Use it for empty-state starters ("Summarize a document") and for
/// follow-ups after a response. An empty [suggestions] list renders nothing,
/// so it is safe to include unconditionally.
class SuggestionChips extends StatelessWidget {
  /// The suggestions to offer.
  final List<Suggestion> suggestions;

  /// Called with the chosen suggestion's [Suggestion.effectiveValue].
  final ValueChanged<String> onSelected;

  /// Lay out in a single horizontally scrolling row instead of wrapping.
  ///
  /// Better above an input bar, where vertical space is scarce.
  final bool scrollable;

  /// Padding around the chip group.
  final EdgeInsets? padding;

  /// Whether chips are interactive.
  final bool enabled;

  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.scrollable = false,
    this.padding,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = AgentTheme.of(context);

    final chips = [
      for (final suggestion in suggestions)
        _Chip(
          suggestion: suggestion,
          onTap: enabled
              ? () => onSelected(suggestion.effectiveValue)
              : null,
        ),
    ];

    if (scrollable) {
      return SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding ??
              EdgeInsets.symmetric(horizontal: theme.spacing.md),
          itemCount: chips.length,
          separatorBuilder: (_, __) => SizedBox(width: theme.spacing.sm),
          itemBuilder: (_, i) => chips[i],
        ),
      );
    }

    return Padding(
      padding: padding ?? EdgeInsets.symmetric(horizontal: theme.spacing.md),
      child: Wrap(
        spacing: theme.spacing.sm,
        runSpacing: theme.spacing.sm,
        alignment: WrapAlignment.center,
        children: chips,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Suggestion suggestion;
  final VoidCallback? onTap;

  const _Chip({required this.suggestion, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(100),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.md,
            vertical: theme.spacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (suggestion.icon != null) ...[
                Icon(suggestion.icon, size: 15, color: colors.accent),
                SizedBox(width: theme.spacing.xs + 2),
              ],
              Text(
                suggestion.label,
                style: theme.typography.bodySmall
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
