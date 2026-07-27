import 'package:flutter/material.dart';

import '../theme/agent_theme.dart';

/// Pulsing dots signalling that the assistant is working.
///
/// Use it inline inside a streaming [ChatBubble], or standalone before the
/// first token arrives. When the platform requests reduced motion the dots
/// render statically — the meaning survives without the animation.
class TypingIndicator extends StatefulWidget {
  /// Dot color. Defaults to the theme's secondary text color.
  final Color? color;

  /// Diameter of each dot.
  final double dotSize;

  /// How many dots to show.
  final int dotCount;

  /// Duration of one full wave.
  final Duration period;

  /// Screen-reader description.
  final String semanticLabel;

  const TypingIndicator({
    super.key,
    this.color,
    this.dotSize = 6,
    this.dotCount = 3,
    this.period = const Duration(milliseconds: 1100),
    this.semanticLabel = 'Assistant is typing',
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Driving an endless repeat under "reduce motion" would keep the device
    // rendering at 60fps for no visual benefit, so only start when animation
    // is actually wanted.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _controller.duration = widget.period;
      if (_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AgentTheme.of(context).colors.textSecondary;

    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: SizedBox(
        height: widget.dotSize * 2,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.dotCount, (i) {
                // Stagger each dot a fixed fraction of the cycle so the wave
                // reads left-to-right regardless of dot count.
                final offset = i / (widget.dotCount * 1.6);
                final t = (_controller.value - offset) % 1.0;
                final wave = 1 - (2 * t - 1).abs();
                final opacity = 0.35 + 0.65 * wave;
                final lift = -2.0 * wave;

                return Padding(
                  padding: EdgeInsets.only(
                    right: i < widget.dotCount - 1 ? widget.dotSize * 0.7 : 0,
                  ),
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// A standalone "thinking" row: avatar-aligned dots inside a bubble shape.
///
/// Shown while waiting for the first token, when there is not yet a message
/// to attach a [TypingIndicator] to.
class ThinkingBubble extends StatelessWidget {
  /// Optional label rendered beside the dots, e.g. "Searching the web".
  final String? label;

  /// Leading avatar, matching the one used on assistant bubbles.
  final Widget? avatar;

  const ThinkingBubble({super.key, this.label, this.avatar});

  @override
  Widget build(BuildContext context) {
    final theme = AgentTheme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.xs,
        horizontal: theme.spacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (avatar != null) ...[avatar!, SizedBox(width: theme.spacing.sm)],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.lg,
              vertical: theme.spacing.md,
            ),
            decoration: BoxDecoration(
              color: theme.colors.assistantBubble,
              borderRadius: theme.radii.largeRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TypingIndicator(color: theme.colors.textSecondary),
                if (label != null) ...[
                  SizedBox(width: theme.spacing.sm),
                  Text(
                    label!,
                    style: theme.typography.caption.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
