import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/agent_theme.dart';
import 'chat_bubble.dart';
import 'message_actions.dart';
import 'message_editor.dart';

/// Builds the avatar shown beside [message], or null for no avatar.
typedef AvatarBuilder = Widget? Function(
  BuildContext context,
  ChatMessage message,
);

/// Builds a replacement widget for [message], or null to use the default
/// [ChatBubble].
typedef MessageBuilder = Widget? Function(
  BuildContext context,
  ChatMessage message,
);

/// A scrolling conversation view with grouping, auto-scroll and a
/// jump-to-latest control.
///
/// Auto-scroll only follows new content while the user is already near the
/// bottom. Scrolling up to re-read something and being yanked back down by
/// the next token is the single most irritating bug in hand-rolled chat UIs,
/// so this treats "scrolled up" as intent and stops following until the user
/// returns.
class MessageList extends StatefulWidget {
  /// Messages in chronological order.
  final List<ChatMessage> messages;

  /// Scroll controller. One is created internally when null.
  final ScrollController? controller;

  /// Supplies avatars. Return null to omit one for a given message.
  ///
  /// Takes priority over [userAvatar] and [agentAvatar] when set — those two
  /// are the convenience path for the common case of one fixed avatar per
  /// role; reach for this when the avatar needs to vary per message (a
  /// per-user profile photo, a tool-specific icon).
  final AvatarBuilder? avatarBuilder;

  /// Fixed avatar shown beside every user message.
  ///
  /// Ignored when [avatarBuilder] is set. Typically an [AgentAvatar] with a
  /// custom `image` or `initials`, but any widget works.
  final Widget? userAvatar;

  /// Fixed avatar shown beside every assistant message.
  ///
  /// Ignored when [avatarBuilder] is set.
  final Widget? agentAvatar;

  /// Overrides rendering for specific messages. Return null to fall back to
  /// the default bubble.
  final MessageBuilder? messageBuilder;

  /// Whether bubbles show timestamps.
  final bool showTimestamps;

  /// Whether assistant bubbles show the copy/regenerate/feedback row.
  final bool showActions;

  /// Formats timestamps. Defaults to 24-hour `HH:mm`.
  final TimestampFormatter? timestampFormatter;

  /// Called when a markdown link is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Called with the message the user wants regenerated.
  final ValueChanged<ChatMessage>? onRegenerate;

  /// Called with the message the user wants retried after a failure.
  final ValueChanged<ChatMessage>? onRetry;

  /// Called with a user message and its rewritten text.
  ///
  /// Enables the edit affordance on user bubbles. The list swaps the bubble
  /// for an inline editor and calls this once the user confirms.
  final void Function(ChatMessage message, String newText)? onEditMessage;

  /// Called when the user rates a message.
  final void Function(ChatMessage message, MessageFeedback feedback)?
      onFeedback;

  /// Widget shown when [messages] is empty.
  final Widget? emptyState;

  /// Pinned above the first message, inside the scroll view.
  final Widget? header;

  /// Pinned below the last message, inside the scroll view.
  final Widget? footer;

  /// Scroll view padding.
  final EdgeInsets? padding;

  /// Scroll physics.
  final ScrollPhysics? physics;

  /// Whether to show the floating jump-to-latest button.
  final bool showScrollToBottom;

  /// How close to the bottom counts as "following", in logical pixels.
  final double autoScrollThreshold;

  /// Whether message text can be selected.
  ///
  /// Selection is scoped to one bubble at a time: a single [SelectionArea]
  /// spanning the list would sit above the [Scrollable], which crashes on
  /// drag-select once a message grows taller than the viewport. Set this to
  /// false and wrap the list yourself only if you accept that behavior.
  final bool selectable;

  const MessageList({
    super.key,
    required this.messages,
    this.controller,
    this.avatarBuilder,
    this.userAvatar,
    this.agentAvatar,
    this.messageBuilder,
    this.showTimestamps = false,
    this.showActions = false,
    this.timestampFormatter,
    this.onLinkTap,
    this.onRegenerate,
    this.onRetry,
    this.onEditMessage,
    this.onFeedback,
    this.emptyState,
    this.header,
    this.footer,
    this.padding,
    this.physics,
    this.showScrollToBottom = true,
    this.autoScrollThreshold = 120,
    this.selectable = true,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  ScrollController? _internalController;
  bool _following = true;
  bool _showJumpButton = false;

  /// Id of the message currently open in the inline editor, if any.
  String? _editingId;

  ScrollController get _controller =>
      widget.controller ?? (_internalController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)?.removeListener(_onScroll);
      _controller.addListener(_onScroll);
    }
    // Drop the editor if its message went away — cleared conversation, or a
    // switch to a different one. Otherwise it would linger over a message
    // that no longer exists.
    if (_editingId != null &&
        !widget.messages.any((m) => m.id == _editingId)) {
      _editingId = null;
    }
    // Content changed — follow it only if the user has not scrolled away.
    // Length alone is not enough: streaming mutates the last message in place.
    final grew = widget.messages.length != oldWidget.messages.length;
    final tailChanged = widget.messages.isNotEmpty &&
        oldWidget.messages.isNotEmpty &&
        widget.messages.last != oldWidget.messages.last;
    if ((grew || tailChanged) && _following) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    (widget.controller ?? _internalController)?.removeListener(_onScroll);
    _internalController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final atBottom = distanceFromBottom <= widget.autoScrollThreshold;

    if (atBottom != _following) _following = atBottom;

    final shouldShow = widget.showScrollToBottom && !atBottom;
    if (shouldShow != _showJumpButton && mounted) {
      setState(() => _showJumpButton = shouldShow);
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  Future<void> _animateToBottom() async {
    if (!_controller.hasClients) return;
    _following = true;
    final motion = AgentTheme.motionOf(context);
    await _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: motion.normal == Duration.zero
          ? const Duration(milliseconds: 1)
          : motion.normal,
      curve: motion.standard,
    );
  }

  /// Where [index] sits within a run of consecutive same-author messages.
  BubbleGroupPosition _groupPositionFor(int index) {
    final messages = widget.messages;
    final current = messages[index];

    bool sameAuthor(int i) {
      if (i < 0 || i >= messages.length) return false;
      if (messages[i].role != current.role) return false;
      // A long pause starts a new group even from the same author.
      final gap = messages[i].createdAt.difference(current.createdAt).abs();
      return gap.inMinutes < 3;
    }

    final prev = sameAuthor(index - 1);
    final next = sameAuthor(index + 1);

    if (!prev && !next) return BubbleGroupPosition.single;
    if (!prev) return BubbleGroupPosition.first;
    if (!next) return BubbleGroupPosition.last;
    return BubbleGroupPosition.middle;
  }

  Widget? _avatarFor(BuildContext context, ChatMessage message) {
    final builder = widget.avatarBuilder;
    if (builder != null) return builder(context, message);

    return switch (message.role) {
      ChatRole.user => widget.userAvatar,
      ChatRole.assistant => widget.agentAvatar,
      ChatRole.system => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final messages = widget.messages;

    if (messages.isEmpty && widget.emptyState != null) {
      return widget.emptyState!;
    }

    final hasHeader = widget.header != null;
    final hasFooter = widget.footer != null;
    final itemCount =
        messages.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0);

    return Stack(
      children: [
        // Each bubble gets its own SelectionArea rather than one wrapping the
        // whole list. A SelectionArea above a Scrollable installs an
        // auto-scroller that asserts the drag target fits inside the viewport,
        // so dragging a selection through a message taller than the screen
        // crashes with "Drag target size is larger than scrollable size".
        // Per-bubble scoping keeps text selectable and sidesteps that entirely.
        Builder(
          builder: (context) => ListView.builder(
            controller: _controller,
            physics: widget.physics,
            padding: widget.padding ??
                EdgeInsets.symmetric(vertical: theme.spacing.md),
            itemCount: itemCount,
            itemBuilder: (context, rawIndex) {
              var index = rawIndex;
              if (hasHeader) {
                if (index == 0) return widget.header!;
                index -= 1;
              }
              if (hasFooter && index == messages.length) return widget.footer!;

              final message = messages[index];

              if (_editingId == message.id) {
                return MessageEditor(
                  key: ValueKey('edit-${message.id}'),
                  initialText: message.text,
                  onCancel: () => setState(() => _editingId = null),
                  onSubmit: (text) {
                    setState(() => _editingId = null);
                    widget.onEditMessage!(message, text);
                  },
                );
              }

              final custom = widget.messageBuilder?.call(context, message);
              if (custom != null) return custom;

              final groupPosition = _groupPositionFor(index);
              // Only the last bubble in a run carries the avatar; the others
              // reserve its width so the column stays aligned -- but only
              // when *this message's own role* actually produces one.
              // Reserving space just because the other role has an avatar
              // left unwanted empty space beside every bubble of a role that
              // never shows one (e.g. the default: no userAvatar configured
              // while the assistant gets one), and it did not respect
              // showAvatars: false at all, since ChatScreen always supplies
              // a non-null avatarBuilder that simply returns null per call.
              final showAvatar =
                  groupPosition == BubbleGroupPosition.single ||
                      groupPosition == BubbleGroupPosition.last;
              final roleAvatar = _avatarFor(context, message);

              final bubble = ChatBubble(
                key: ValueKey(message.id),
                message: message,
                avatar: showAvatar ? roleAvatar : null,
                reserveAvatarSpace: !showAvatar && roleAvatar != null,
                groupPosition: groupPosition,
                showTimestamp: widget.showTimestamps &&
                    (groupPosition == BubbleGroupPosition.single ||
                        groupPosition == BubbleGroupPosition.last),
                timestampFormatter: widget.timestampFormatter,
                showActions: widget.showActions,
                onLinkTap: widget.onLinkTap,
                onRegenerate: widget.onRegenerate == null
                    ? null
                    : () => widget.onRegenerate!(message),
                onRetry: widget.onRetry == null
                    ? null
                    : () => widget.onRetry!(message),
                onEdit: (widget.onEditMessage != null &&
                        message.role == ChatRole.user)
                    ? () => setState(() => _editingId = message.id)
                    : null,
                onFeedback: widget.onFeedback == null
                    ? null
                    : (feedback) => widget.onFeedback!(message, feedback),
              );

              return widget.selectable
                  ? SelectionArea(key: ValueKey('sel-${message.id}'), child: bubble)
                  : bubble;
            },
          ),
        ),
        if (widget.showScrollToBottom)
          Positioned(
            right: theme.spacing.lg,
            bottom: theme.spacing.lg,
            child: _JumpToLatestButton(
              visible: _showJumpButton,
              onPressed: _animateToBottom,
            ),
          ),
      ],
    );
  }
}

class _JumpToLatestButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onPressed;

  const _JumpToLatestButton({required this.visible, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final motion = AgentTheme.motionOf(context);
    final colors = theme.colors;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: motion.fast,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.4),
          duration: motion.fast,
          curve: motion.standard,
          child: Semantics(
            button: true,
            label: 'Jump to latest message',
            child: Material(
              color: colors.surfaceContainer,
              shape: CircleBorder(
                side: BorderSide(color: colors.border),
              ),
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
