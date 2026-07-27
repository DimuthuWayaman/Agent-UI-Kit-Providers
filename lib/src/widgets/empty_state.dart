import 'package:flutter/material.dart';

import '../theme/agent_theme.dart';
import 'suggestion_chips.dart';

/// The zero-state shown before a conversation has any messages.
///
/// A blank chat is the worst first impression an assistant can make; this
/// gives the user a title, a hint at what the agent can do, and concrete
/// starters to tap.
class ChatEmptyState extends StatelessWidget {
  /// Large heading, e.g. "How can I help?".
  final String title;

  /// Supporting line beneath the title.
  final String? subtitle;

  /// Icon or illustration above the title.
  final Widget? icon;

  /// Starter prompts offered to the user.
  final List<Suggestion> suggestions;

  /// Called when a starter is chosen.
  final ValueChanged<String>? onSuggestionSelected;

  const ChatEmptyState({
    super.key,
    this.title = 'How can I help?',
    this.subtitle,
    this.icon,
    this.suggestions = const [],
    this.onSuggestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(theme.spacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon ??
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.accentSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 26,
                      color: colors.accent,
                    ),
                  ),
              SizedBox(height: theme.spacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.typography.heading1
                    .copyWith(color: colors.textPrimary),
              ),
              if (subtitle != null) ...[
                SizedBox(height: theme.spacing.sm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.typography.bodySmall
                      .copyWith(color: colors.textSecondary),
                ),
              ],
              if (suggestions.isNotEmpty &&
                  onSuggestionSelected != null) ...[
                SizedBox(height: theme.spacing.xl),
                SuggestionChips(
                  suggestions: suggestions,
                  onSelected: onSuggestionSelected!,
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
