import 'package:flutter/material.dart';

import '../controllers/chat_controller.dart';
import '../controllers/conversation_controller.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../theme/agent_theme.dart';
import 'agent_avatar.dart';
import 'chat_history_drawer.dart';
import 'chat_input_bar.dart';
import 'empty_state.dart';
import 'message_actions.dart';
import 'message_list.dart';
import 'suggestion_chips.dart';

/// A complete chat surface: message list, empty state, suggestions and
/// composer, wired to a [ChatController].
///
/// This is the "one widget and you have a working agent UI" entry point.
/// Everything it composes is public, so you can drop down to [MessageList] +
/// [ChatInputBar] whenever you outgrow it.
///
/// ```dart
/// ChatScreen(
///   controller: ChatController(responder: (m) => client.stream(m.text)),
///   title: 'Assistant',
/// )
/// ```
class ChatScreen extends StatefulWidget {
  /// Conversation state. The screen listens to it and rebuilds.
  final ChatController controller;

  /// Optional app bar title. No app bar is shown when null.
  final String? title;

  /// Actions placed in the app bar.
  final List<Widget> appBarActions;

  /// Composer placeholder.
  final String hintText;

  /// Starters offered in the empty state.
  final List<Suggestion> suggestions;

  /// Follow-ups shown above the composer once a conversation is under way.
  final List<Suggestion> followUps;

  /// Replaces the default empty state.
  final Widget? emptyState;

  /// Empty-state heading.
  final String emptyTitle;

  /// Empty-state supporting line.
  final String? emptySubtitle;

  /// Whether bubbles show timestamps.
  final bool showTimestamps;

  /// Whether assistant bubbles show copy/regenerate/feedback actions.
  final bool showActions;

  /// Whether to show avatars beside messages.
  final bool showAvatars;

  /// Supplies avatars, overriding the built-in [AgentAvatar].
  ///
  /// Takes priority over [userAvatar] and [agentAvatar]. Reach for this only
  /// when the avatar must vary per message; for one fixed avatar per role,
  /// [userAvatar] and [agentAvatar] are simpler.
  final AvatarBuilder? avatarBuilder;

  /// Fixed avatar shown beside every user message.
  ///
  /// Unset by default — user messages are already right-aligned, so a second
  /// "this is you" marker is usually redundant. Set this to show one anyway,
  /// e.g. the signed-in user's profile photo. Ignored when [avatarBuilder] is
  /// set, and has no effect when [showAvatars] is false.
  final Widget? userAvatar;

  /// Fixed avatar shown beside every assistant message.
  ///
  /// Defaults to [AgentAvatar] when unset. Ignored when [avatarBuilder] is
  /// set, and has no effect when [showAvatars] is false.
  final Widget? agentAvatar;

  /// Called when a markdown link is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Called when the attach button is tapped. Button hidden when null.
  final VoidCallback? onAttach;

  /// Called when the mic button is tapped. Button hidden when null.
  final VoidCallback? onVoice;

  /// Pending attachments shown in the composer.
  final List<Attachment> attachments;

  /// Called with the index of an attachment to remove.
  final ValueChanged<int>? onRemoveAttachment;

  /// Called when the user rates a message.
  final void Function(ChatMessage message, MessageFeedback feedback)?
      onFeedback;

  /// Background behind the whole screen, e.g. a gradient for the glass theme.
  final Widget? background;

  /// Overrides the send behavior. Defaults to [ChatController.send].
  ///
  /// Provide this when the controller has no responder and you drive
  /// streaming yourself.
  final ValueChanged<String>? onSend;

  /// Conversation history. When set, the screen gains a history drawer and a
  /// new-chat action, and [controller] should be its
  /// [ConversationController.chat].
  final ConversationController? conversations;

  /// Whether user messages can be edited and resent.
  ///
  /// Editing discards everything after the edited message, since replies to
  /// the old wording no longer belong to the thread.
  final bool allowEditing;

  /// Whether to show the new-chat action in the app bar.
  ///
  /// Defaults to true when [conversations] is supplied.
  final bool? showNewChatAction;

  const ChatScreen({
    super.key,
    required this.controller,
    this.title,
    this.appBarActions = const [],
    this.hintText = 'Message…',
    this.suggestions = const [],
    this.followUps = const [],
    this.emptyState,
    this.emptyTitle = 'How can I help?',
    this.emptySubtitle,
    this.showTimestamps = false,
    this.showActions = true,
    this.showAvatars = true,
    this.avatarBuilder,
    this.userAvatar,
    this.agentAvatar,
    this.onLinkTap,
    this.onAttach,
    this.onVoice,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.onFeedback,
    this.background,
    this.onSend,
    this.conversations,
    this.allowEditing = true,
    this.showNewChatAction,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.conversations?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (widget.conversations != oldWidget.conversations) {
      oldWidget.conversations?.removeListener(_onControllerChanged);
      widget.conversations?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    // Both controllers are owned by the caller; only stop listening to them.
    widget.controller.removeListener(_onControllerChanged);
    widget.conversations?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _startNewChat() {
    final conversations = widget.conversations;
    if (conversations != null) {
      conversations.newConversation();
    } else {
      // Without history there is nowhere to file the old thread, so a new
      // chat is simply an empty one.
      widget.controller.clear();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleSend(String text) {
    final onSend = widget.onSend;
    if (onSend != null) {
      onSend(text);
    } else {
      widget.controller.send(text, attachments: widget.attachments);
    }
  }

  Widget? _buildAvatar(BuildContext context, ChatMessage message) {
    if (widget.avatarBuilder != null) {
      return widget.avatarBuilder!(context, message);
    }
    if (!widget.showAvatars) return null;

    return switch (message.role) {
      // User messages are already right-aligned, so a second "this is you"
      // marker is redundant by default — but an explicit userAvatar means
      // the caller wants one anyway (a profile photo, say).
      ChatRole.user => widget.userAvatar,
      ChatRole.assistant =>
        widget.agentAvatar ?? const AgentAvatar(role: ChatRole.assistant),
      ChatRole.system => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final controller = widget.controller;
    final messages = controller.messages;

    final content = Column(
      children: [
        Expanded(
          child: MessageList(
            messages: messages,
            avatarBuilder: _buildAvatar,
            showTimestamps: widget.showTimestamps,
            showActions: widget.showActions,
            onLinkTap: widget.onLinkTap,
            onFeedback: widget.onFeedback,
            onRegenerate: (_) => controller.retryLast(),
            onRetry: (_) => controller.retryLast(),
            onEditMessage: widget.allowEditing
                ? (message, text) => controller.editMessage(message.id, text)
                : null,
            emptyState: widget.emptyState ??
                ChatEmptyState(
                  title: widget.emptyTitle,
                  subtitle: widget.emptySubtitle,
                  suggestions: widget.suggestions,
                  onSuggestionSelected: _handleSend,
                ),
          ),
        ),
        if (widget.followUps.isNotEmpty && messages.isNotEmpty) ...[
          SizedBox(height: theme.spacing.sm),
          SuggestionChips(
            suggestions: widget.followUps,
            onSelected: _handleSend,
            scrollable: true,
            enabled: !controller.isStreaming,
          ),
        ],
        SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(
            theme.spacing.md,
            theme.spacing.sm,
            theme.spacing.md,
            theme.spacing.md,
          ),
          child: ChatInputBar(
            onSend: _handleSend,
            onStop: controller.stop,
            onAttach: widget.onAttach,
            onVoice: widget.onVoice,
            isStreaming: controller.isStreaming,
            hintText: widget.hintText,
            attachments: widget.attachments,
            onRemoveAttachment: widget.onRemoveAttachment,
          ),
        ),
      ],
    );

    final conversations = widget.conversations;
    final showNewChat = widget.showNewChatAction ?? conversations != null;

    // AppBar prefers the drawer hamburger over the back button whenever a
    // drawer exists, so a pushed chat screen with history would have no way
    // back. When both are wanted, the leading slot goes to the back button
    // and history moves into the actions.
    final canPop = Navigator.of(context).canPop();
    final showHistoryAction = conversations != null && canPop;

    final actions = <Widget>[
      if (showHistoryAction)
        IconButton(
          tooltip: 'Chat history',
          icon: const Icon(Icons.history_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      if (showNewChat)
        IconButton(
          tooltip: 'New chat',
          icon: const Icon(Icons.add_comment_outlined),
          // Starting a new chat mid-response would orphan the stream, so it
          // waits until the current one finishes.
          onPressed: controller.isStreaming ? null : _startNewChat,
        ),
      ...widget.appBarActions,
    ];

    // An app bar is required to reach the drawer, so one is synthesized when
    // history is enabled but no title was given.
    final needsAppBar = widget.title != null || conversations != null;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          widget.background != null ? Colors.transparent : theme.colors.surface,
      drawer: conversations == null
          ? null
          : ChatHistoryDrawer(
              controller: conversations,
              onSelected: () => Navigator.of(context).maybePop(),
            ),
      appBar: !needsAppBar
          ? null
          : AppBar(
              title: Text(widget.title ?? ''),
              leading: showHistoryAction ? const BackButton() : null,
              backgroundColor: theme.colors.surface,
              foregroundColor: theme.colors.textPrimary,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              actions: actions,
            ),
      body: widget.background == null
          ? content
          : Stack(
              children: [
                Positioned.fill(child: widget.background!),
                content,
              ],
            ),
    );
  }
}
