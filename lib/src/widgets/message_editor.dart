import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agent_theme.dart';

/// Inline editor shown in place of a user bubble while its prompt is being
/// rewritten.
///
/// Editing happens where the message already sits rather than in a dialog, so
/// the surrounding conversation stays visible — the context you need in order
/// to decide how to reword it.
class MessageEditor extends StatefulWidget {
  /// The text to start from.
  final String initialText;

  /// Called with the new text when the user confirms.
  final ValueChanged<String> onSubmit;

  /// Called when the user abandons the edit.
  final VoidCallback onCancel;

  /// Maximum lines before the field scrolls.
  final int maxLines;

  const MessageEditor({
    super.key,
    required this.initialText,
    required this.onSubmit,
    required this.onCancel,
    this.maxLines = 10,
  });

  @override
  State<MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<MessageEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Open with the caret at the end and the keyboard already up: the user
    // asked to edit, so there is no reason to make them tap again.
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialText.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    if (shift) return KeyEventResult.ignored;

    _submit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.md,
        vertical: theme.spacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.maxBubbleWidth),
          child: Container(
            padding: EdgeInsets.all(theme.spacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: theme.radii.largeRadius,
              border: Border.all(color: colors.accent, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: widget.maxLines,
                    keyboardType: TextInputType.multiline,
                    style: theme.typography.body
                        .copyWith(color: colors.textPrimary),
                    cursorColor: colors.accent,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                SizedBox(height: theme.spacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        textStyle: theme.typography.bodySmall,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Cancel'),
                    ),
                    SizedBox(width: theme.spacing.sm),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        final canSend = value.text.trim().isNotEmpty;
                        return FilledButton(
                          onPressed: canSend ? _submit : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.onAccent,
                            textStyle: theme.typography.bodySmall,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.symmetric(
                              horizontal: theme.spacing.lg,
                              vertical: theme.spacing.sm,
                            ),
                          ),
                          child: const Text('Send'),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
