import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/agent_theme.dart';

/// A circular avatar for a conversation participant.
///
/// Resolves in priority order: [image], then [icon], then [initials], then a
/// role-appropriate default glyph — so it always renders something sensible
/// even with no configuration.
class AgentAvatar extends StatelessWidget {
  /// Whose avatar this is. Drives the default glyph and colors.
  final ChatRole role;

  /// Optional image, e.g. a user photo or model logo.
  final ImageProvider? image;

  /// Optional icon, used when [image] is absent.
  final IconData? icon;

  /// Optional initials, used when [image] and [icon] are absent.
  final String? initials;

  /// Diameter. Defaults to the theme's avatar size.
  final double? size;

  /// Background color. Defaults to a role-appropriate tint.
  final Color? backgroundColor;

  /// Foreground color for the icon or initials.
  final Color? foregroundColor;

  /// Small status ring, e.g. green while the agent is active.
  final Color? statusColor;

  const AgentAvatar({
    super.key,
    required this.role,
    this.image,
    this.icon,
    this.initials,
    this.size,
    this.backgroundColor,
    this.foregroundColor,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final diameter = size ?? theme.avatarSize;

    final background = backgroundColor ??
        switch (role) {
          ChatRole.user => colors.surfaceContainerHigh,
          ChatRole.assistant => colors.accentSubtle,
          ChatRole.system => colors.systemBubble,
        };

    final foreground = foregroundColor ??
        switch (role) {
          ChatRole.user => colors.textSecondary,
          ChatRole.assistant => colors.accent,
          ChatRole.system => colors.onSystemBubble,
        };

    Widget content;
    if (image != null) {
      content = Image(image: image!, fit: BoxFit.cover);
    } else if (icon != null) {
      content = Icon(icon, size: diameter * 0.55, color: foreground);
    } else if (initials != null && initials!.trim().isNotEmpty) {
      content = Text(
        _normalizeInitials(initials!),
        style: theme.typography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: diameter * 0.36,
        ),
      );
    } else {
      content = Icon(
        switch (role) {
          ChatRole.user => Icons.person_rounded,
          ChatRole.assistant => Icons.auto_awesome_rounded,
          ChatRole.system => Icons.info_outline_rounded,
        },
        size: diameter * 0.55,
        color: foreground,
      );
    }

    Widget avatar = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (statusColor != null) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: diameter * 0.32,
              height: diameter * 0.32,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: switch (role) {
        ChatRole.user => 'You',
        ChatRole.assistant => 'Assistant',
        ChatRole.system => 'System',
      },
      child: ExcludeSemantics(child: avatar),
    );
  }

  /// Takes at most the first two initials and uppercases them.
  static String _normalizeInitials(String raw) {
    final parts =
        raw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final only = parts.first;
      return (only.length <= 2 ? only : only.substring(0, 2)).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}
