import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agent_theme.dart';

/// The thumbs-up / thumbs-down verdict a user can give a message.
enum MessageFeedback {
  /// The response was good.
  positive,

  /// The response was bad.
  negative,
}

/// A compact row of actions shown beneath a message: copy, regenerate and
/// optional feedback.
///
/// Every action is opt-in — passing no callbacks renders nothing, so the bar
/// can be attached unconditionally and stay invisible until an app wires up
/// the behavior it supports.
class MessageActionBar extends StatefulWidget {
  /// Text placed on the clipboard by the copy action.
  ///
  /// When null, the copy button is hidden.
  final String? copyText;

  /// Called when the user asks for the message to be regenerated.
  final VoidCallback? onRegenerate;

  /// Called when the user wants to rewrite this message. Hidden when null.
  final VoidCallback? onEdit;

  /// Called when the user rates the message.
  final ValueChanged<MessageFeedback>? onFeedback;

  /// The rating already given, so the chosen button can render as selected.
  final MessageFeedback? feedback;

  /// Extra trailing actions, e.g. "read aloud" or "share".
  final List<Widget> extraActions;

  /// Whether the bar is currently interactive.
  final bool enabled;

  const MessageActionBar({
    super.key,
    this.copyText,
    this.onRegenerate,
    this.onEdit,
    this.onFeedback,
    this.feedback,
    this.extraActions = const [],
    this.enabled = true,
  });

  /// Whether this configuration would render anything at all.
  bool get hasAnyAction =>
      copyText != null ||
      onRegenerate != null ||
      onEdit != null ||
      onFeedback != null ||
      extraActions.isNotEmpty;

  @override
  State<MessageActionBar> createState() => _MessageActionBarState();
}

class _MessageActionBarState extends State<MessageActionBar> {
  bool _copied = false;

  Future<void> _copy() async {
    final text = widget.copyText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasAnyAction) return const SizedBox.shrink();

    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    // No top padding here: this bar is composed inline, beside the
    // timestamp, in ChatBubble's single footer row -- that row's own
    // padding controls the gap to the bubble above.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.copyText != null)
          _ActionButton(
            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
            tooltip: _copied ? 'Copied' : 'Copy',
            color: _copied ? colors.success : null,
            onPressed: widget.enabled ? _copy : null,
          ),
        if (widget.onEdit != null)
          _ActionButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onPressed: widget.enabled ? widget.onEdit : null,
          ),
        if (widget.onRegenerate != null)
          _ActionButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Regenerate',
            onPressed: widget.enabled ? widget.onRegenerate : null,
          ),
        if (widget.onFeedback != null) ...[
          _ActionButton(
            icon: widget.feedback == MessageFeedback.positive
                ? Icons.thumb_up_rounded
                : Icons.thumb_up_outlined,
            tooltip: 'Good response',
            color: widget.feedback == MessageFeedback.positive
                ? colors.accent
                : null,
            onPressed: widget.enabled
                ? () => widget.onFeedback!(MessageFeedback.positive)
                : null,
          ),
          _ActionButton(
            icon: widget.feedback == MessageFeedback.negative
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            tooltip: 'Bad response',
            color: widget.feedback == MessageFeedback.negative
                ? colors.error
                : null,
            onPressed: widget.enabled
                ? () => widget.onFeedback!(MessageFeedback.negative)
                : null,
          ),
        ],
        ...widget.extraActions,
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return IconButton(
      icon: Icon(icon, size: 15),
      color: color ?? theme.colors.textTertiary,
      onPressed: onPressed,
      tooltip: tooltip,
      // A small glyph inside a tight hit area: unobtrusive next to the
      // message. 28x28 keeps neighboring action icons close together
      // instead of leaving a wide gap between them (was 40x32, which read
      // as too much whitespace both between icons and below the row).
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
    );
  }
}
