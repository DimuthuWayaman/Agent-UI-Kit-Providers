import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/attachment.dart';
import '../theme/agent_theme.dart';
import 'attachment_preview.dart';

/// Message composer: auto-growing field, attachment tray, and a send button
/// that morphs into a stop button while a response streams.
///
/// Supply a [controller] to read or preset the draft; otherwise one is
/// created and disposed internally.
class ChatInputBar extends StatefulWidget {
  /// Called with the trimmed text when the user sends.
  final ValueChanged<String> onSend;

  /// Called when the user stops an in-flight response.
  final VoidCallback? onStop;

  /// Called when the attach button is tapped. Button hidden when null.
  final VoidCallback? onAttach;

  /// Called when the microphone button is tapped. Button hidden when null.
  final VoidCallback? onVoice;

  /// Whether a response is currently streaming.
  final bool isStreaming;

  /// Whether the composer accepts input.
  final bool enabled;

  /// Placeholder text.
  final String hintText;

  /// Pending attachments shown above the field.
  final List<Attachment> attachments;

  /// Called with the index of an attachment to remove.
  final ValueChanged<int>? onRemoveAttachment;

  /// External text controller. One is created internally when null.
  final TextEditingController? controller;

  /// External focus node. One is created internally when null.
  final FocusNode? focusNode;

  /// Maximum lines before the field starts scrolling.
  final int maxLines;

  /// Character limit. Shows a counter as the limit approaches.
  final int? maxLength;

  /// Whether a bare Enter sends the message.
  ///
  /// Defaults to true on desktop and web (where Shift+Enter inserts a
  /// newline) and false on mobile, where Enter should insert a newline and
  /// the send button is the only way to submit. That split matches what users
  /// already expect on each platform.
  final bool? sendOnEnter;

  /// Whether to clear the field after sending.
  final bool clearOnSend;

  /// Whether to keep focus after sending, so the user can keep typing.
  final bool retainFocusOnSend;

  /// Extra widgets placed between the attach button and the text field.
  final List<Widget> leadingActions;

  /// Extra widgets placed between the text field and the send button.
  final List<Widget> trailingActions;

  /// Outer padding.
  final EdgeInsets? padding;

  /// Corner radius of the bar.
  ///
  /// Defaults to a perfect capsule in the single-line state: the radius is
  /// exactly half the collapsed height, so the ends are true semicircles
  /// rather than a rounded rectangle. When the field grows to multiple lines
  /// or shows attachments the radius stays put, which keeps the tall state
  /// from turning into a stretched oval.
  final BorderRadius? borderRadius;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onStop,
    this.onAttach,
    this.onVoice,
    this.isStreaming = false,
    this.enabled = true,
    this.hintText = 'Message…',
    this.attachments = const [],
    this.onRemoveAttachment,
    this.controller,
    this.focusNode,
    this.maxLines = 6,
    this.maxLength,
    this.sendOnEnter,
    this.clearOnSend = true,
    this.retainFocusOnSend = true,
    this.leadingActions = const [],
    this.trailingActions = const [],
    this.padding,
    this.borderRadius,
  });

  /// Height of the send button and the other circular actions.
  ///
  /// The text field is pinned to this same height so that, on a single line,
  /// every element in the row is exactly as tall as its neighbours.
  static const double controlSize = 38;

  /// Width of the bar's outline.
  ///
  /// Counted in [collapsedHeight] because a border grows the box on both
  /// sides; leaving it out makes the computed radius fall short and the ends
  /// render as flats instead of semicircles.
  static const double borderWidth = 1;

  /// The bar's height with a single line of text and no attachments.
  static double collapsedHeight(EdgeInsets padding) =>
      controlSize + padding.top + padding.bottom + borderWidth * 2;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;
  bool _hasText = false;

  // Guards _submit() against firing twice for one logical send (rapid
  // double-Enter or a fast double-tap on the send button). This matters most
  // for an attachment-only send: widget.attachments is owned by the parent,
  // so it only reflects a post-send removal once the parent rebuilds this
  // widget -- until then a second _submit() call would still see the old,
  // non-empty list and fire onSend('') again.
  bool _sending = false;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _hasText = _controller.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_onTextChanged);
      _controller.addListener(_onTextChanged);
      _onTextChanged();
    }
  }

  void _onTextChanged() {
    if (!mounted) return;
    final hasText = _controller.text.trim().isNotEmpty;
    final hasTextChanged = hasText != _hasText;
    // The counter in build() reads _controller.text.length directly, so once
    // maxLength is set it needs a rebuild on every keystroke -- not only when
    // hasText flips between empty and non-empty -- or it freezes at whatever
    // length happened to be showing on the last unrelated rebuild.
    if (hasTextChanged || widget.maxLength != null) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    // Only dispose what this widget created; an externally supplied
    // controller belongs to the caller.
    (widget.controller ?? _internalController)?.removeListener(_onTextChanged);
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  bool get _sendOnEnter {
    if (widget.sendOnEnter != null) return widget.sendOnEnter!;
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  bool get _attachmentsUploading =>
      widget.attachments.any((a) => a.isUploading);

  bool get _canSend =>
      widget.enabled &&
      !_attachmentsUploading &&
      (_hasText || widget.attachments.isNotEmpty);

  void _submit() {
    if (_sending || !_canSend) return;
    _sending = true;
    final text = _controller.text.trim();
    widget.onSend(text);
    if (widget.clearOnSend) _controller.clear();
    // The composer doesn't own the attachment list (it's supplied by the
    // caller), so sending clears it by asking the caller to remove every
    // attachment rather than mutating anything locally.
    if (widget.onRemoveAttachment != null) {
      for (var i = widget.attachments.length - 1; i >= 0; i--) {
        widget.onRemoveAttachment!(i);
      }
    }
    if (widget.retainFocusOnSend) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    // Released after this frame, by which point the parent's rebuild (e.g.
    // clearing widget.attachments in response to onRemoveAttachment above)
    // has landed -- that's what actually closes the race, not just a fixed
    // delay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sending = false;
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_sendOnEnter) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    // Shift+Enter is the universal "newline without sending" gesture.
    if (shift) return KeyEventResult.ignored;

    _submit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final motion = AgentTheme.motionOf(context);
    final colors = theme.colors;

    final counter = widget.maxLength != null
        ? _buildCounter(theme)
        : const SizedBox.shrink();

    final padding = widget.padding ?? EdgeInsets.all(theme.spacing.sm);
    // Exactly half the collapsed height closes the ends into true
    // semicircles. Anything less leaves a flat edge, which is what reads as
    // a rounded rectangle rather than a capsule.
    final radius = widget.borderRadius ??
        BorderRadius.circular(ChatInputBar.collapsedHeight(padding) / 2);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: radius,
        border: Border.all(
          color: colors.border,
          width: ChatInputBar.borderWidth,
        ),
        boxShadow: theme.elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: theme.elevation * 3,
                  offset: Offset(0, theme.elevation),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.attachments.isNotEmpty)
            Padding(
              // The container already supplies the outer inset; this only
              // separates the tray from the field below it.
              padding: EdgeInsets.only(
                left: theme.spacing.xs,
                bottom: theme.spacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AttachmentPreviewList(
                  attachments: widget.attachments,
                  onRemove: widget.onRemoveAttachment,
                  compact: true,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.onAttach != null)
                _CircleAction(
                  icon: Icons.add_rounded,
                  tooltip: 'Attach file',
                  onPressed: widget.enabled ? widget.onAttach : null,
                ),
              ...widget.leadingActions,
              Expanded(
                child: ConstrainedBox(
                  // Pins the collapsed field to the control height so a
                  // single line sits flush with the buttons; taller content
                  // still grows past it.
                  constraints: const BoxConstraints(
                    minHeight: ChatInputBar.controlSize,
                  ),
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: widget.maxLines,
                      maxLength: widget.maxLength,
                      // The default counter sits outside the bar and breaks
                      // its shape; a custom one is rendered below instead.
                      buildCounter: _noCounter,
                      textInputAction: _sendOnEnter
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _sendOnEnter ? (_) => _submit() : null,
                      style: theme.typography.body
                          .copyWith(color: colors.textPrimary),
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: theme.typography.body
                            .copyWith(color: colors.textTertiary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        // Vertical padding is deliberately smaller than the
                        // spacing scale: one line of body text plus this
                        // padding must land on controlSize, or the field
                        // outgrows the buttons beside it.
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: theme.spacing.sm,
                          vertical: theme.spacing.sm,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ...widget.trailingActions,
              if (widget.onVoice != null && !_hasText && !widget.isStreaming)
                _CircleAction(
                  icon: Icons.mic_none_rounded,
                  tooltip: 'Voice input',
                  onPressed: widget.enabled ? widget.onVoice : null,
                ),
              SizedBox(width: theme.spacing.xs),
              _SendButton(
                isStreaming: widget.isStreaming,
                enabled: widget.isStreaming ? true : _canSend,
                duration: motion.fast,
                onPressed: widget.isStreaming ? widget.onStop : _submit,
              ),
            ],
          ),
          counter,
        ],
      ),
    );
  }

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) =>
      null;

  Widget _buildCounter(AgentThemeData theme) {
    final max = widget.maxLength!;
    final length = _controller.text.length;
    // Stay out of the way until the limit is actually in sight.
    if (length < max * 0.8) return const SizedBox.shrink();

    final overLimit = length >= max;
    return Padding(
      padding: EdgeInsets.only(
        right: theme.spacing.md,
        bottom: theme.spacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$length / $max',
          style: theme.typography.caption.copyWith(
            color: overLimit ? theme.colors.error : theme.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isStreaming;
  final bool enabled;
  final Duration duration;
  final VoidCallback? onPressed;

  const _SendButton({
    required this.isStreaming,
    required this.enabled,
    required this.duration,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final active = enabled && onPressed != null;

    return Semantics(
      button: true,
      enabled: active,
      label: isStreaming ? 'Stop generating' : 'Send message',
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        width: ChatInputBar.controlSize,
        height: ChatInputBar.controlSize,
        decoration: BoxDecoration(
          color: active
              ? colors.accent
              : colors.accent.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: active ? onPressed : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  isStreaming
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  key: ValueKey(isStreaming),
                  size: 19,
                  color: colors.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _CircleAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AgentTheme.of(context).colors;

    return IconButton(
      icon: Icon(icon, size: 21),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(
        width: ChatInputBar.controlSize,
        height: ChatInputBar.controlSize,
      ),
      style: IconButton.styleFrom(
        foregroundColor: colors.textSecondary,
        // An IconButton otherwise reserves a 48dp tap target no matter what
        // its constraints say, laying out 10dp taller than the field and send
        // button beside it and leaving dead space above them.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size.square(ChatInputBar.controlSize),
        maximumSize: const Size.square(ChatInputBar.controlSize),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
