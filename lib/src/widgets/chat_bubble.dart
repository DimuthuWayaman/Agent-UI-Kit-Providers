import 'package:flutter/material.dart';

import '../markdown/markdown_view.dart';
import '../models/chat_message.dart';
import '../theme/agent_theme.dart';
import 'attachment_preview.dart';
import 'citation_chip.dart';
import 'message_actions.dart';
import 'tool_call_card.dart';
import 'typing_indicator.dart';

/// Formats a message timestamp for display.
typedef TimestampFormatter = String Function(DateTime timestamp);

/// Formats an elapsed [Duration] for display as the response-time caption,
/// e.g. "2.3s".
typedef ResponseTimeFormatter = String Function(Duration duration);

/// Formats the interrupted-message caption. [elapsed] is
/// [ChatMessage.responseTime], which may be null.
typedef InterruptedFormatter = String Function(Duration? elapsed);

/// Where a bubble sits within a run of consecutive messages from the same
/// author. Drives corner rounding and avatar visibility so a run reads as one
/// group rather than a stack of identical pills.
enum BubbleGroupPosition {
  /// The only message in its run.
  single,

  /// The first of several.
  first,

  /// Between the first and last.
  middle,

  /// The last of several.
  last,
}

/// A single chat message: markdown body, attachments, tool calls, citations,
/// status and actions.
///
/// The primary constructor takes a [ChatMessage]. For quick one-off usage
/// there is [ChatBubble.text], which builds a message for you.
class ChatBubble extends StatelessWidget {
  /// The message to render.
  final ChatMessage message;

  /// Avatar shown beside the bubble. Pass null to hide it.
  final Widget? avatar;

  /// Whether to reserve avatar space when [avatar] is null, keeping bubbles
  /// in a run aligned with each other.
  final bool reserveAvatarSpace;

  /// Whether to render the timestamp under the bubble.
  final bool showTimestamp;

  /// Converts [ChatMessage.createdAt] to display text.
  ///
  /// Defaults to 24-hour `HH:mm`. The kit takes no `intl` dependency, so pass
  /// your own formatter for locale-aware output.
  final TimestampFormatter? timestampFormatter;

  /// Whether to show how long the assistant took to respond.
  ///
  /// Shown at the opposite edge of the bubble from the timestamp/actions
  /// row (not right next to it) once [ChatMessage.status] is
  /// [MessageStatus.sent] and [ChatMessage.responseTime] is available —
  /// keeping it visually separate from the timestamp avoids the two being
  /// mistaken for each other.
  final bool showResponseTime;

  /// Converts [ChatMessage.responseTime] to display text.
  ///
  /// Defaults to just the duration, e.g. "2.3s" — no surrounding words, so
  /// it stays compact.
  final ResponseTimeFormatter? responseTimeFormatter;

  /// Text style for the response-time caption.
  ///
  /// Defaults to `theme.typography.caption` colored with
  /// `theme.colors.textTertiary`.
  final TextStyle? responseTimeStyle;

  /// Icon shown before the response-time caption, distinguishing it at a
  /// glance from the timestamp.
  final IconData responseTimeIcon;

  /// Converts [ChatMessage.responseTime] to the interrupted-message caption,
  /// shown when [ChatMessage.status] is [MessageStatus.stopped].
  ///
  /// Defaults to "Interrupted" or, when a duration is available,
  /// "Interrupted after 2.3s".
  final InterruptedFormatter? interruptedFormatter;

  /// Icon shown next to the interrupted-message caption.
  final IconData interruptedIcon;

  /// Color applied to the interrupted indicator's icon, and to its text
  /// unless [interruptedTextStyle] overrides the color itself.
  ///
  /// Defaults to `theme.colors.warning`.
  final Color? interruptedColor;

  /// Text style for the interrupted-message caption.
  ///
  /// Defaults to `theme.typography.caption` colored with [interruptedColor].
  final TextStyle? interruptedTextStyle;

  /// Position within a run of same-author messages.
  final BubbleGroupPosition groupPosition;

  /// Called when a markdown link is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Called when the user asks to regenerate this message.
  final VoidCallback? onRegenerate;

  /// Called when the user retries a failed message.
  final VoidCallback? onRetry;

  /// Called when the user wants to rewrite this prompt.
  ///
  /// Only offered on user messages. Hidden when null.
  final VoidCallback? onEdit;

  /// Called when the user rates this message.
  final ValueChanged<MessageFeedback>? onFeedback;

  /// The rating already recorded for this message.
  final MessageFeedback? feedback;

  /// Called when an attachment is tapped.
  final ValueChanged<int>? onAttachmentTap;

  /// Called when a citation is tapped.
  final ValueChanged<int>? onCitationTap;

  /// Whether to show the copy/regenerate/feedback row beneath the bubble.
  ///
  /// Actions are suppressed while streaming regardless — copying a
  /// half-finished response is rarely what the user means.
  final bool showActions;

  /// Whether to render tool calls above the message text.
  final bool showToolCalls;

  /// Outer margin.
  final EdgeInsets? margin;

  const ChatBubble({
    super.key,
    required this.message,
    this.avatar,
    this.reserveAvatarSpace = false,
    this.showTimestamp = false,
    this.timestampFormatter,
    this.showResponseTime = false,
    this.responseTimeFormatter,
    this.responseTimeStyle,
    this.responseTimeIcon = Icons.timer_outlined,
    this.interruptedFormatter,
    this.interruptedIcon = Icons.stop_circle_outlined,
    this.interruptedColor,
    this.interruptedTextStyle,
    this.groupPosition = BubbleGroupPosition.single,
    this.onLinkTap,
    this.onRegenerate,
    this.onRetry,
    this.onEdit,
    this.onFeedback,
    this.feedback,
    this.onAttachmentTap,
    this.onCitationTap,
    this.showActions = false,
    this.showToolCalls = true,
    this.margin,
  });

  /// Convenience constructor for rendering raw text without building a
  /// [ChatMessage] first.
  ChatBubble.text(
    String text, {
    Key? key,
    required ChatRole role,
    bool isStreaming = false,
    Widget? avatar,
    ValueChanged<String>? onLinkTap,
    EdgeInsets? margin,
  }) : this(
          key: key,
          message: ChatMessage(
            id: 'inline-${text.hashCode}-${role.index}',
            role: role,
            text: text,
            status:
                isStreaming ? MessageStatus.streaming : MessageStatus.sent,
          ),
          avatar: avatar,
          onLinkTap: onLinkTap,
          margin: margin,
        );

  bool get _isUser => message.role == ChatRole.user;
  bool get _isSystem => message.role == ChatRole.system;

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final motion = AgentTheme.motionOf(context);
    final colors = theme.colors;

    if (_isSystem) return _buildSystem(context, theme);

    final bubbleColor = _isUser ? colors.userBubble : colors.assistantBubble;
    final textColor =
        _isUser ? colors.onUserBubble : colors.onAssistantBubble;

    // Attachments render as their own edge-to-edge tiles rather than inside
    // the accent-colored bubble: a photo or file chip wrapped in bubble
    // padding/color reads as a mismatched "container within a container".
    // Only the text (and the streaming indicator) get the colored bubble.
    final attachments = message.attachments.isEmpty
        ? null
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
            child: AttachmentPreviewList(
              attachments: message.attachments,
              onTap: onAttachmentTap,
              compact: true,
            ),
          );

    final body = <Widget>[];

    if (message.text.isNotEmpty) {
      body.add(
        message.isMarkdown
            ? MarkdownView(
                data: message.text,
                textColor: textColor,
                onLinkTap: onLinkTap,
                isStreaming: message.isStreaming,
              )
            : Text(
                message.text,
                style: theme.typography.body.copyWith(color: textColor),
              ),
      );
    }

    // An assistant message with no content yet is waiting on its first token;
    // the dots stand in for the body rather than trailing it.
    if (message.isStreaming && message.isEmpty) {
      body.add(TypingIndicator(color: textColor.withValues(alpha: 0.6)));
    } else if (message.isStreaming) {
      body.add(SizedBox(height: theme.spacing.xs));
      body.add(TypingIndicator(color: textColor.withValues(alpha: 0.6)));
    }

    final bubble = body.isEmpty
        ? null
        : Container(
            padding: theme.bubblePadding,
            constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: _resolveRadius(theme),
              border: message.hasFailed
                  ? Border.all(color: colors.error.withValues(alpha: 0.6))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: body,
            ),
          );

    final column = Column(
      crossAxisAlignment:
          _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showToolCalls && message.toolCalls.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final call in message.toolCalls)
                  ToolCallCard(toolCall: call, margin: EdgeInsets.zero),
                SizedBox(height: theme.spacing.xs),
              ],
            ),
          ),
        if (attachments != null) attachments,
        if (attachments != null && bubble != null)
          SizedBox(height: theme.spacing.sm),
        if (bubble != null) bubble,
        if (message.citations.isNotEmpty) ...[
          SizedBox(height: theme.spacing.xs),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
            child: CitationList(
              citations: message.citations,
              onTap: onCitationTap,
            ),
          ),
        ],
        if (message.hasFailed) _buildError(context, theme),
        if (message.wasStopped) _buildInterrupted(context, theme),
        _buildFooter(context, theme),
      ],
    );

    final row = Row(
      mainAxisAlignment:
          _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isUser) ..._leading(theme),
        Flexible(child: column),
        if (_isUser) ..._trailing(theme),
      ],
    );

    return Semantics(
      container: true,
      label: _semanticLabel(),
      child: AnimatedSize(
        duration: motion.fast,
        curve: motion.standard,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: margin ?? _defaultMargin(theme),
          child: row,
        ),
      ),
    );
  }

  List<Widget> _leading(AgentThemeData theme) {
    if (avatar != null) {
      return [avatar!, SizedBox(width: theme.spacing.sm)];
    }
    if (reserveAvatarSpace) {
      return [SizedBox(width: theme.avatarSize + theme.spacing.sm)];
    }
    return const [];
  }

  List<Widget> _trailing(AgentThemeData theme) {
    if (avatar != null) {
      return [SizedBox(width: theme.spacing.sm), avatar!];
    }
    if (reserveAvatarSpace) {
      return [SizedBox(width: theme.avatarSize + theme.spacing.sm)];
    }
    return const [];
  }

  EdgeInsets _defaultMargin(AgentThemeData theme) {
    // Messages inside a run sit closer together than separate turns do.
    final tight = groupPosition == BubbleGroupPosition.middle ||
        groupPosition == BubbleGroupPosition.last;
    return EdgeInsets.symmetric(
      horizontal: theme.spacing.md,
      vertical: tight ? theme.spacing.xs / 2 : theme.spacing.xs,
    );
  }

  /// Squares off the corner facing the previous/next message in a run so the
  /// group reads as one connected shape.
  BorderRadius _resolveRadius(AgentThemeData theme) {
    final r = Radius.circular(theme.radii.lg);
    const tight = Radius.circular(6);
    if (groupPosition == BubbleGroupPosition.single) {
      return BorderRadius.all(r);
    }

    final topInner = groupPosition == BubbleGroupPosition.first ? r : tight;
    final bottomInner = groupPosition == BubbleGroupPosition.last ? r : tight;

    return _isUser
        ? BorderRadius.only(
            topLeft: r,
            bottomLeft: r,
            topRight: topInner,
            bottomRight: bottomInner,
          )
        : BorderRadius.only(
            topRight: r,
            bottomRight: r,
            topLeft: topInner,
            bottomLeft: bottomInner,
          );
  }

  Widget _buildSystem(BuildContext context, AgentThemeData theme) {
    final colors = theme.colors;
    return Padding(
      padding: margin ??
          EdgeInsets.symmetric(
            horizontal: theme.spacing.md,
            vertical: theme.spacing.sm,
          ),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.md,
            vertical: theme.spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.systemBubble,
            borderRadius: theme.radii.mediumRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: colors.onSystemBubble,
              ),
              SizedBox(width: theme.spacing.sm),
              Flexible(
                child: Text(
                  message.text,
                  style: theme.typography.bodySmall
                      .copyWith(color: colors.onSystemBubble),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, AgentThemeData theme) {
    final colors = theme.colors;
    return Padding(
      padding: EdgeInsets.only(top: theme.spacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: colors.error),
          SizedBox(width: theme.spacing.xs),
          Flexible(
            child: Text(
              message.error ?? 'Something went wrong',
              style: theme.typography.caption.copyWith(color: colors.error),
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(width: theme.spacing.sm),
            InkWell(
              onTap: onRetry,
              borderRadius: theme.radii.smallRadius,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing.sm,
                  vertical: 2,
                ),
                child: Text(
                  'Retry',
                  style: theme.typography.caption.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInterrupted(BuildContext context, AgentThemeData theme) {
    final color = interruptedColor ?? theme.colors.warning;
    final text =
        (interruptedFormatter ?? _defaultInterrupted)(message.responseTime);
    return Padding(
      padding: EdgeInsets.only(top: theme.spacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(interruptedIcon, size: 14, color: color),
          SizedBox(width: theme.spacing.xs),
          Flexible(
            child: Text(
              text,
              style: interruptedTextStyle ??
                  theme.typography.caption.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AgentThemeData theme) {
    final showActionRow = showActions && !message.isStreaming;

    // User messages get copy + edit; assistant messages get copy, regenerate
    // and feedback. Editing an assistant reply is meaningless, and
    // regenerating a prompt is what editing already does.
    final actions = showActionRow
        ? MessageActionBar(
            copyText: message.text.isEmpty ? null : message.text,
            onRegenerate: _isUser ? null : onRegenerate,
            onEdit: _isUser ? onEdit : null,
            onFeedback: _isUser ? null : onFeedback,
            feedback: feedback,
          )
        : null;

    final responseTimeText = showResponseTime &&
            message.status == MessageStatus.sent &&
            message.responseTime != null
        ? (responseTimeFormatter ?? _defaultResponseTime)(
            message.responseTime!,
          )
        : null;

    final metaTextStyle =
        theme.typography.caption.copyWith(color: theme.colors.textTertiary);

    final timestamp = showTimestamp
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  (timestampFormatter ?? _defaultTimestamp)(
                    message.createdAt,
                  ),
                  style: metaTextStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isUser) ...[
                SizedBox(width: theme.spacing.xs),
                _statusIcon(theme),
              ],
            ],
          )
        : null;

    final responseTime = responseTimeText != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                responseTimeIcon,
                size: 12,
                color: responseTimeStyle?.color ?? theme.colors.textTertiary,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  responseTimeText,
                  style: responseTimeStyle ?? metaTextStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: theme.spacing.sm),
            ],
          )
        : null;

    if (actions == null && timestamp == null && responseTime == null) {
      return const SizedBox.shrink();
    }

    // Actions and timestamp sit side by side in one row, not stacked, and
    // right against the bubble above -- both were previously pushed apart
    // (a Column) and away from the bubble (this padding plus
    // MessageActionBar's own top padding, now removed since the row-level
    // gap below replaces it). Only built when there's something to put in
    // it -- the response-time-only case below has no use for an empty Row.
    final leading = actions == null && timestamp == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (actions != null) actions,
              if (actions != null && timestamp != null)
                SizedBox(width: theme.spacing.sm),
              if (timestamp != null) Flexible(child: timestamp),
            ],
          );

    if (responseTime == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [leading!],
      );
    }

    // Response time is pinned to the opposite edge of the bubble from
    // actions/timestamp, rather than sitting right next to them -- two
    // numbers side by side in the same spot read as one ambiguous cluster,
    // so they get their own corner instead. Both sides are Flexible so a
    // long custom responseTimeFormatter result (or a large accessibility
    // text scale) ellipsizes instead of overflowing the bubble.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) Flexible(child: leading) else const Spacer(),
          Flexible(child: responseTime),
        ],
      ),
    );
  }

  Widget _statusIcon(AgentThemeData theme) {
    final colors = theme.colors;
    return switch (message.status) {
      MessageStatus.sending => SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            valueColor: AlwaysStoppedAnimation(colors.textTertiary),
          ),
        ),
      MessageStatus.sent =>
        Icon(Icons.done_rounded, size: 12, color: colors.textTertiary),
      MessageStatus.streaming =>
        Icon(Icons.more_horiz_rounded, size: 12, color: colors.textTertiary),
      MessageStatus.failed =>
        Icon(Icons.error_outline_rounded, size: 12, color: colors.error),
      MessageStatus.stopped =>
        Icon(Icons.stop_circle_outlined, size: 12, color: colors.warning),
    };
  }

  String _semanticLabel() {
    final who = switch (message.role) {
      ChatRole.user => 'You said',
      ChatRole.assistant => 'Assistant said',
      ChatRole.system => 'System notice',
    };
    if (message.isStreaming && message.isEmpty) return 'Assistant is replying';
    return '$who: ${message.text}';
  }

  static String _defaultTimestamp(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _defaultResponseTime(Duration d) => _formatDuration(d);

  static String _defaultInterrupted(Duration? d) =>
      d == null ? 'Interrupted' : 'Interrupted after ${_formatDuration(d)}';

  static String _formatDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    if (d.inMinutes < 1) {
      return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
