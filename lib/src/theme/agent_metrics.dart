import 'package:flutter/material.dart';

/// The spacing scale. Every gap in the kit is a multiple of these values,
/// which is what keeps rhythm consistent between bubbles, cards and inputs.
@immutable
class AgentSpacing {
  /// 4dp — icon-to-label gaps.
  final double xs;

  /// 8dp — tight internal padding.
  final double sm;

  /// 12dp — default internal padding.
  final double md;

  /// 16dp — bubble padding, screen gutters.
  final double lg;

  /// 24dp — section separation.
  final double xl;

  const AgentSpacing({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
  });

  /// Multiplies the whole scale, useful for compact/comfortable density modes.
  AgentSpacing scaled(double factor) => AgentSpacing(
        xs: xs * factor,
        sm: sm * factor,
        md: md * factor,
        lg: lg * factor,
        xl: xl * factor,
      );

  AgentSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return AgentSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  /// Linearly interpolates between two spacing scales.
  static AgentSpacing lerp(AgentSpacing a, AgentSpacing b, double t) {
    return AgentSpacing(
      xs: lerpDouble(a.xs, b.xs, t),
      sm: lerpDouble(a.sm, b.sm, t),
      md: lerpDouble(a.md, b.md, t),
      lg: lerpDouble(a.lg, b.lg, t),
      xl: lerpDouble(a.xl, b.xl, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentSpacing &&
        other.xs == xs &&
        other.sm == sm &&
        other.md == md &&
        other.lg == lg &&
        other.xl == xl;
  }

  @override
  int get hashCode => Object.hash(xs, sm, md, lg, xl);
}

/// Corner radii used across the kit.
@immutable
class AgentRadii {
  /// Radius for chips and small controls.
  final double sm;

  /// Radius for tool cards and code blocks.
  final double md;

  /// Radius for message bubbles.
  final double lg;

  /// Radius for the input bar and sheets.
  final double xl;

  const AgentRadii({
    this.sm = 8,
    this.md = 12,
    this.lg = 18,
    this.xl = 24,
  });

  /// Convenience [BorderRadius] for [sm].
  BorderRadius get smallRadius => BorderRadius.circular(sm);

  /// Convenience [BorderRadius] for [md].
  BorderRadius get mediumRadius => BorderRadius.circular(md);

  /// Convenience [BorderRadius] for [lg].
  BorderRadius get largeRadius => BorderRadius.circular(lg);

  /// Convenience [BorderRadius] for [xl].
  BorderRadius get extraLargeRadius => BorderRadius.circular(xl);

  AgentRadii copyWith({double? sm, double? md, double? lg, double? xl}) {
    return AgentRadii(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  /// Linearly interpolates between two radius scales.
  static AgentRadii lerp(AgentRadii a, AgentRadii b, double t) {
    return AgentRadii(
      sm: lerpDouble(a.sm, b.sm, t),
      md: lerpDouble(a.md, b.md, t),
      lg: lerpDouble(a.lg, b.lg, t),
      xl: lerpDouble(a.xl, b.xl, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentRadii &&
        other.sm == sm &&
        other.md == md &&
        other.lg == lg &&
        other.xl == xl;
  }

  @override
  int get hashCode => Object.hash(sm, md, lg, xl);
}

/// Animation durations and curves.
///
/// Centralizing motion means an app can globally slow things down, speed them
/// up, or disable them for accessibility without editing widgets.
@immutable
class AgentMotion {
  /// Micro-interactions: button state changes, hover.
  final Duration fast;

  /// Default: expand/collapse, bubble entrance.
  final Duration normal;

  /// Deliberate: theme cross-fades, sheet transitions.
  final Duration slow;

  /// Curve for entrances and expansions.
  final Curve standard;

  /// Curve for playful, attention-drawing motion.
  final Curve emphasized;

  const AgentMotion({
    this.fast = const Duration(milliseconds: 120),
    this.normal = const Duration(milliseconds: 220),
    this.slow = const Duration(milliseconds: 400),
    this.standard = Curves.easeOutCubic,
    this.emphasized = Curves.easeOutBack,
  });

  /// A motion profile with all durations set to zero.
  ///
  /// Widgets select this automatically when the platform reports
  /// "reduce motion"; see `AgentTheme.motionOf`.
  static const AgentMotion none = AgentMotion(
    fast: Duration.zero,
    normal: Duration.zero,
    slow: Duration.zero,
    standard: Curves.linear,
    emphasized: Curves.linear,
  );

  AgentMotion copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Curve? standard,
    Curve? emphasized,
  }) {
    return AgentMotion(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      standard: standard ?? this.standard,
      emphasized: emphasized ?? this.emphasized,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentMotion &&
        other.fast == fast &&
        other.normal == normal &&
        other.slow == slow &&
        other.standard == standard &&
        other.emphasized == emphasized;
  }

  @override
  int get hashCode => Object.hash(fast, normal, slow, standard, emphasized);
}

/// Interpolates between two doubles. Local helper so the theme layer does not
/// need to import `dart:ui`.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;
