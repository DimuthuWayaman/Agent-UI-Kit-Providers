import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// Whether assistant bubbles show how long they took to respond.
  ///
  /// Fine-grained styling (formatter, icon, color) is available on
  /// [MessageList] directly.
  final bool showResponseTime;

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

  /// Conversation history. When set, the screen *can* gain a history drawer
  /// and a new-chat action, and [controller] should be its
  /// [ConversationController.chat]. Whether the drawer actually appears is
  /// controlled separately by [showHistory] — supplying a controller here
  /// doesn't force the drawer on, e.g. a host that still wants
  /// [ConversationController] for persistence but not the built-in UI can
  /// pass this and set [showHistory] to false. What the drawer looks like is
  /// controlled by [historyDrawerBuilder].
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

  /// Whether the history drawer and its app-bar entry point appear at all.
  ///
  /// Defaults to true; only has an effect when [conversations] is supplied.
  /// Set to false to keep a [ConversationController] wired up (for its own
  /// persistence/state needs) without exposing the built-in history UI.
  final bool showHistory;

  /// Builds the history drawer, overriding the built-in [ChatHistoryDrawer].
  ///
  /// Called with the same [ConversationController] passed as [conversations].
  /// Use this to change [ChatHistoryDrawer]'s own options (title, search,
  /// footer actions) or to swap in a completely different widget. Ignored
  /// when [conversations] is null or [showHistory] is false.
  final Widget Function(BuildContext context, ConversationController conversations)?
      historyDrawerBuilder;

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
    this.showResponseTime = false,
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
    this.showHistory = true,
    this.historyDrawerBuilder,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // The real, measured height of the follow-ups/composer group that floats
  // over the message list. Drives how much bottom padding the list reserves
  // for its own scroll content — measured rather than guessed, so a tall
  // composer (multi-line draft, an attachment tray) can never end up
  // covering content the reservation didn't account for.
  double? _bottomGroupHeight;

  void _onBottomGroupSize(Size size) {
    if (!mounted || size.height == _bottomGroupHeight) return;
    setState(() => _bottomGroupHeight = size.height);
  }

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
    final colors = theme.colors;
    final controller = widget.controller;
    final messages = controller.messages;

    final conversations = widget.conversations;
    final showNewChat = widget.showNewChatAction ?? conversations != null;

    // `conversations` supplies the controller; `showHistory` decides whether
    // the drawer UI it enables actually appears (a host can keep the
    // controller wired up for its own persistence needs while hiding the
    // built-in drawer).
    final hasHistoryDrawer = conversations != null && widget.showHistory;

    // AppBar prefers the drawer hamburger over the back button whenever a
    // drawer exists, so a pushed chat screen with history would have no way
    // back. When both are wanted, the leading slot goes to the back button
    // and history moves into the actions.
    final canPop = Navigator.of(context).canPop();
    final showHistoryAction = hasHistoryDrawer && canPop;

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
    final needsAppBar = widget.title != null || hasHistoryDrawer;
    final hasCustomBackground = widget.background != null;
    final hasFollowUps = widget.followUps.isNotEmpty && messages.isNotEmpty;

    // The page's own background color, opaque, to tint/gradient the frosted
    // bits below toward — "a little dark/light, whichever the theme is".
    // The glass palette has no fixed surface color of its own (it's
    // `Colors.transparent`, meant to sit on a caller-supplied backdrop), so
    // it falls back to a plain dark/light base derived from brightness
    // instead of forcing alpha onto a color with no RGB of its own.
    final scrimBase = colors.surface == Colors.transparent
        ? (theme.brightness == Brightness.dark ? Colors.black : Colors.white)
        : colors.surface;

    final composer = SafeArea(
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
    );

    // Follow-up chips (if any) and the composer, floating over the message
    // list rather than pushing it up — the list's own scroll content runs
    // underneath (see `Positioned.fill` below) and gets blurred through the
    // panel behind this group, the bottom-edge mirror of what the app bar
    // already does at the top.
    final bottomGroup = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasFollowUps) ...[
          // Was a tight `spacing.sm`, easy to misread as still part of the
          // last bubble rather than a separate follow-up affordance.
          SizedBox(height: theme.spacing.xl),
          SuggestionChips(
            suggestions: widget.followUps,
            onSelected: _handleSend,
            scrollable: true,
            enabled: !controller.isStreaming,
          ),
        ],
        composer,
      ],
    );

    // Fades the panel in from nothing at its own top edge instead of
    // starting on a hard line — the blur/tint ramps up gradually as it
    // passes behind the group, mirroring the app bar's fade in the
    // opposite direction.
    final bottomGroupWithFade = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.white],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: scrimBase.withValues(alpha: 1)),
                ),
              ),
            ),
          ),
        ),
        bottomGroup,
      ],
    );

    final topInset = needsAppBar
        ? MediaQuery.paddingOf(context).top + kToolbarHeight + theme.spacing.md
        : theme.spacing.md;

    // One frame's worth of fallback only, for before the group below has
    // ever been laid out (and so `_bottomGroupHeight` is still null) — once
    // it has, the measured height is the real reservation, so a tall
    // composer/attachment tray can never end up covering content that
    // padding didn't account for.
    final chipsFallback =
        hasFollowUps ? 38 + theme.spacing.xl : 0.0;
    final composerFallback = theme.spacing.sm +
        ChatInputBar.collapsedHeight(EdgeInsets.all(theme.spacing.sm)) +
        (MediaQuery.paddingOf(context).bottom > theme.spacing.md
            ? MediaQuery.paddingOf(context).bottom
            : theme.spacing.md);
    final bottomInset = (_bottomGroupHeight ?? (chipsFallback + composerFallback)) +
        theme.spacing.md;

    final content = Stack(
      children: [
        Positioned.fill(
          child: MessageList(
            messages: messages,
            avatarBuilder: _buildAvatar,
            showTimestamps: widget.showTimestamps,
            showResponseTime: widget.showResponseTime,
            showActions: widget.showActions,
            onLinkTap: widget.onLinkTap,
            onFeedback: widget.onFeedback,
            onRegenerate: (_) => controller.retryLast(),
            onRetry: (_) => controller.retryLast(),
            onEditMessage: widget.allowEditing
                ? (message, text) => controller.editMessage(message.id, text)
                : null,
            padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
            emptyState: widget.emptyState ??
                ChatEmptyState(
                  title: widget.emptyTitle,
                  subtitle: widget.emptySubtitle,
                  suggestions: widget.suggestions,
                  onSuggestionSelected: _handleSend,
                ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MeasureSize(
            onChange: _onBottomGroupSize,
            child: bottomGroupWithFade,
          ),
        ),
      ],
    );

    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          hasCustomBackground ? Colors.transparent : colors.surface,
      // Lets the message list run up behind the app bar instead of
      // stopping short of it, so real scrolled content — not just a static
      // backdrop — passes underneath and gets blurred: the same "content
      // slides under a frosted bar" look as the Messages/Mail nav bar on
      // iOS.
      extendBodyBehindAppBar: needsAppBar,
      drawer: !hasHistoryDrawer
          ? null
          : (widget.historyDrawerBuilder?.call(context, conversations) ??
              ChatHistoryDrawer(
                controller: conversations,
                onSelected: () => Navigator.of(context).maybePop(),
              )),
      appBar: !needsAppBar
          ? null
          : AppBar(
              title: Text(widget.title ?? ''),
              leading: showHistoryAction ? const BackButton() : null,
              // Transparent, not tinted: the tint lives entirely inside
              // `flexibleSpace` below so the bottom-edge fade (which fades
              // that layer to nothing) actually reaches full transparency
              // instead of a separately-opaque Material fill still showing
              // through underneath it.
              backgroundColor: Colors.transparent,
              foregroundColor: colors.textPrimary,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              // The mask lets the blur/tint go the rest of the way to fully
              // transparent instead of stopping dead at the bar's bottom
              // edge — it only touches the lower half, well clear of where
              // the title/actions sit, so their opacity is untouched.
              flexibleSpace: ClipRect(
                child: ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.75, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(color: scrimBase.withValues(alpha: 1)),
                  ),
                ),
              ),
              actions: actions,
            ),
      body: content,
    );

    if (!hasCustomBackground) return scaffold;

    // Painted behind the Scaffold as a whole — not inside `body` — so it
    // extends behind the app bar too, letting the frosted app bar above
    // blur the same gradient the message list sits on instead of the
    // Scaffold's own default canvas color.
    return Stack(
      children: [
        Positioned.fill(child: widget.background!),
        scaffold,
      ],
    );
  }
}

/// Reports [child]'s rendered size after every layout pass, deferred to a
/// post-frame callback so it never fires mid-build.
///
/// Used to keep the message list's bottom padding — the space it reserves
/// so its own scroll content passes behind the floating follow-ups/composer
/// group rather than under it — in exact sync with that group's real
/// height, instead of a guess that could fall short.
class _MeasureSize extends SingleChildRenderObjectWidget {
  /// Called whenever the measured size changes.
  final ValueChanged<Size> onChange;

  const _MeasureSize({required this.onChange, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _oldSize;

  _MeasureSizeRenderObject(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}
