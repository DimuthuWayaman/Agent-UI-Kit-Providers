import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tool_call.dart';
import '../theme/agent_theme.dart';

/// Visualizes a single tool/function call: a compact status header that
/// expands to reveal arguments and results.
///
/// This is the piece most Flutter chat kits omit. Agent responses are not
/// just text — showing *what the model did* is what makes an agent UI
/// legible instead of a black box.
class ToolCallCard extends StatefulWidget {
  /// The call to render.
  final ToolCall toolCall;

  /// Whether the details start expanded.
  final bool initiallyExpanded;

  /// Expand automatically when the call fails, so errors are never hidden
  /// behind a tap.
  final bool autoExpandOnError;

  /// Icon shown before the tool name. Defaults to a wrench.
  final IconData? icon;

  /// Outer margin.
  final EdgeInsets? margin;

  /// Called when the header is tapped, in addition to toggling expansion.
  final VoidCallback? onTap;

  /// Whether to show a copy button for the input/output blocks.
  final bool showCopyButtons;

  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.initiallyExpanded = false,
    this.autoExpandOnError = true,
    this.icon,
    this.margin,
    this.onTap,
    this.showCopyButtons = true,
  });

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _expanded = widget.initiallyExpanded ||
      (widget.autoExpandOnError &&
          widget.toolCall.status == ToolCallStatus.error);

  @override
  void didUpdateWidget(ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A call that fails after mounting should reveal its error too, but never
    // re-collapse something the user deliberately opened.
    final becameError = widget.toolCall.status == ToolCallStatus.error &&
        oldWidget.toolCall.status != ToolCallStatus.error;
    if (becameError && widget.autoExpandOnError && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final motion = AgentTheme.motionOf(context);
    final colors = theme.colors;
    final call = widget.toolCall;
    final hasDetails = call.hasDetails;

    return Container(
      margin: widget.margin ??
          EdgeInsets.symmetric(
            vertical: theme.spacing.xs,
            horizontal: theme.spacing.md,
          ),
      decoration: BoxDecoration(
        color: colors.toolSurface,
        borderRadius: theme.radii.mediumRadius,
        border: Border.all(
          color: call.status == ToolCallStatus.error
              ? colors.error.withValues(alpha: 0.4)
              : colors.toolBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: hasDetails,
            expanded: hasDetails ? _expanded : null,
            label: 'Tool ${call.name}, ${_statusLabel(call.status)}',
            child: InkWell(
              onTap: hasDetails
                  ? () {
                      setState(() => _expanded = !_expanded);
                      widget.onTap?.call();
                    }
                  : widget.onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing.md,
                  vertical: theme.spacing.sm + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon ?? Icons.build_rounded,
                      size: 15,
                      color: colors.accent,
                    ),
                    SizedBox(width: theme.spacing.sm),
                    Flexible(
                      child: Text(
                        call.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.label
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                    if (call.readableDuration != null) ...[
                      SizedBox(width: theme.spacing.sm),
                      Text(
                        call.readableDuration!,
                        style: theme.typography.caption
                            .copyWith(color: colors.textTertiary),
                      ),
                    ],
                    const Spacer(),
                    _StatusBadge(status: call.status),
                    if (hasDetails) ...[
                      SizedBox(width: theme.spacing.xs),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: motion.fast,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: motion.normal,
            curve: motion.standard,
            alignment: Alignment.topCenter,
            child: (_expanded && hasDetails)
                ? _Details(
                    call: call,
                    showCopyButtons: widget.showCopyButtons,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(ToolCallStatus status) => switch (status) {
        ToolCallStatus.pending => 'pending',
        ToolCallStatus.running => 'running',
        ToolCallStatus.success => 'succeeded',
        ToolCallStatus.error => 'failed',
        ToolCallStatus.cancelled => 'cancelled',
      };
}

class _StatusBadge extends StatelessWidget {
  final ToolCallStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = AgentTheme.of(context).colors;

    return switch (status) {
      ToolCallStatus.pending => Icon(
          Icons.schedule_rounded,
          size: 15,
          color: colors.textTertiary,
        ),
      ToolCallStatus.running => SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            valueColor: AlwaysStoppedAnimation(colors.accent),
          ),
        ),
      ToolCallStatus.success => Icon(
          Icons.check_circle_rounded,
          size: 15,
          color: colors.success,
        ),
      ToolCallStatus.error => Icon(
          Icons.error_rounded,
          size: 15,
          color: colors.error,
        ),
      ToolCallStatus.cancelled => Icon(
          Icons.cancel_rounded,
          size: 15,
          color: colors.textTertiary,
        ),
    };
  }
}

class _Details extends StatelessWidget {
  final ToolCall call;
  final bool showCopyButtons;

  const _Details({required this.call, required this.showCopyButtons});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.md,
        0,
        theme.spacing.md,
        theme.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (call.input?.isNotEmpty ?? false)
            _Section(
              label: 'INPUT',
              content: call.input!,
              showCopy: showCopyButtons,
            ),
          if (call.output?.isNotEmpty ?? false)
            _Section(
              label: 'OUTPUT',
              content: call.output!,
              showCopy: showCopyButtons,
            ),
          if (call.error?.isNotEmpty ?? false)
            _Section(
              label: 'ERROR',
              content: call.error!,
              showCopy: showCopyButtons,
              isError: true,
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String content;
  final bool showCopy;
  final bool isError;

  const _Section({
    required this.label,
    required this.content,
    required this.showCopy,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);
    final colors = theme.colors;
    final accent = isError ? colors.error : colors.textTertiary;

    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.typography.overline.copyWith(color: accent),
              ),
              const Spacer(),
              if (showCopy)
                _MiniCopyButton(text: content),
            ],
          ),
          SizedBox(height: theme.spacing.xs),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(theme.spacing.sm),
            decoration: BoxDecoration(
              color: colors.codeSurface,
              borderRadius: theme.radii.smallRadius,
              border: Border.all(
                color: isError
                    ? colors.error.withValues(alpha: 0.3)
                    : colors.codeBorder,
              ),
            ),
            // Tool payloads are frequently one long JSON line; scrolling keeps
            // the card from stretching to an unreadable height.
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  content,
                  style: theme.typography.code.copyWith(
                    color: isError ? colors.error : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCopyButton extends StatefulWidget {
  final String text;

  const _MiniCopyButton({required this.text});

  @override
  State<_MiniCopyButton> createState() => _MiniCopyButtonState();
}

class _MiniCopyButtonState extends State<_MiniCopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgentTheme.of(context).colors;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 13,
          color: _copied ? colors.success : colors.textTertiary,
        ),
      ),
    );
  }
}
