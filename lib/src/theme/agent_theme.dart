import 'package:flutter/material.dart';

import 'agent_colors.dart';
import 'agent_metrics.dart';
import 'agent_typography.dart';

/// The complete visual configuration for every widget in agent_ui_kit_providers.
///
/// Compose it from token groups rather than loose properties:
///
/// ```dart
/// AgentTheme(
///   data: AgentThemeData.dark(accent: Colors.teal).copyWith(
///     maxBubbleWidth: 720,
///   ),
///   child: const ChatScreen(...),
/// )
/// ```
@immutable
class AgentThemeData {
  /// Semantic color palette.
  final AgentColors colors;

  /// Typographic scale.
  final AgentTypography typography;

  /// Spacing scale.
  final AgentSpacing spacing;

  /// Corner radii.
  final AgentRadii radii;

  /// Durations and curves.
  final AgentMotion motion;

  /// Whether this theme is light or dark. Drives status-bar icon brightness
  /// and the default code palette.
  final Brightness brightness;

  /// Maximum width a single message bubble may occupy.
  ///
  /// Long lines are hard to read; on wide screens bubbles stop growing here
  /// rather than spanning the full window.
  final double maxBubbleWidth;

  /// Internal padding of a message bubble.
  final EdgeInsets bubblePadding;

  /// Diameter of avatars rendered beside bubbles.
  final double avatarSize;

  /// Elevation applied to the input bar and floating controls.
  ///
  /// Set to zero for a flat, borders-only aesthetic.
  final double elevation;

  const AgentThemeData({
    required this.colors,
    required this.typography,
    this.spacing = const AgentSpacing(),
    this.radii = const AgentRadii(),
    this.motion = const AgentMotion(),
    this.brightness = Brightness.light,
    this.maxBubbleWidth = 560,
    this.bubblePadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    this.avatarSize = 28,
    this.elevation = 0,
  });

  /// The default light theme.
  factory AgentThemeData.light({
    Color accent = const Color(0xFF6C5CE7),
    String? fontFamily,
  }) {
    return AgentThemeData(
      colors: AgentColors.light(accent: accent),
      typography: AgentTypography.standard(fontFamily: fontFamily),
      brightness: Brightness.light,
    );
  }

  /// The default dark theme.
  factory AgentThemeData.dark({
    Color accent = const Color(0xFF8B7CF6),
    String? fontFamily,
  }) {
    return AgentThemeData(
      colors: AgentColors.dark(accent: accent),
      typography: AgentTypography.standard(fontFamily: fontFamily),
      brightness: Brightness.dark,
    );
  }

  /// A translucent theme intended to sit on a gradient or image backdrop.
  ///
  /// Widgets in the kit read [AgentColors.surfaceContainer] alpha and apply a
  /// backdrop blur when it is translucent, so this reads as frosted glass.
  factory AgentThemeData.glass({
    Color accent = const Color(0xFF8B7CF6),
    String? fontFamily,
  }) {
    return AgentThemeData(
      colors: AgentColors.glass(accent: accent),
      typography: AgentTypography.standard(fontFamily: fontFamily),
      brightness: Brightness.dark,
    );
  }

  /// Derives a theme from the host app's Material [ThemeData].
  ///
  /// This is what [AgentTheme.of] falls back to when no [AgentTheme] is
  /// present, so the kit adopts the surrounding app's brand colors with no
  /// configuration at all.
  factory AgentThemeData.fromTheme(ThemeData theme) {
    return AgentThemeData(
      colors: AgentColors.fromColorScheme(theme.colorScheme),
      typography: AgentTypography.standard(
        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      ),
      brightness: theme.brightness,
    );
  }

  AgentThemeData copyWith({
    AgentColors? colors,
    AgentTypography? typography,
    AgentSpacing? spacing,
    AgentRadii? radii,
    AgentMotion? motion,
    Brightness? brightness,
    double? maxBubbleWidth,
    EdgeInsets? bubblePadding,
    double? avatarSize,
    double? elevation,
  }) {
    return AgentThemeData(
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      spacing: spacing ?? this.spacing,
      radii: radii ?? this.radii,
      motion: motion ?? this.motion,
      brightness: brightness ?? this.brightness,
      maxBubbleWidth: maxBubbleWidth ?? this.maxBubbleWidth,
      bubblePadding: bubblePadding ?? this.bubblePadding,
      avatarSize: avatarSize ?? this.avatarSize,
      elevation: elevation ?? this.elevation,
    );
  }

  /// Linearly interpolates between two themes.
  ///
  /// Powers [AnimatedAgentTheme]; `t` of 0 returns [a], 1 returns [b].
  static AgentThemeData lerp(AgentThemeData a, AgentThemeData b, double t) {
    return AgentThemeData(
      colors: AgentColors.lerp(a.colors, b.colors, t),
      typography: AgentTypography.lerp(a.typography, b.typography, t),
      spacing: AgentSpacing.lerp(a.spacing, b.spacing, t),
      radii: AgentRadii.lerp(a.radii, b.radii, t),
      // Durations and curves do not interpolate meaningfully — snap at the
      // midpoint so a transition never runs at a half-blended speed.
      motion: t < 0.5 ? a.motion : b.motion,
      brightness: t < 0.5 ? a.brightness : b.brightness,
      maxBubbleWidth: lerpDouble(a.maxBubbleWidth, b.maxBubbleWidth, t),
      bubblePadding: EdgeInsets.lerp(a.bubblePadding, b.bubblePadding, t)!,
      avatarSize: lerpDouble(a.avatarSize, b.avatarSize, t),
      elevation: lerpDouble(a.elevation, b.elevation, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentThemeData &&
        other.colors == colors &&
        other.typography == typography &&
        other.spacing == spacing &&
        other.radii == radii &&
        other.motion == motion &&
        other.brightness == brightness &&
        other.maxBubbleWidth == maxBubbleWidth &&
        other.bubblePadding == bubblePadding &&
        other.avatarSize == avatarSize &&
        other.elevation == elevation;
  }

  @override
  int get hashCode => Object.hash(
        colors,
        typography,
        spacing,
        radii,
        motion,
        brightness,
        maxBubbleWidth,
        bubblePadding,
        avatarSize,
        elevation,
      );
}

/// Provides an [AgentThemeData] to all descendant agent_ui_kit_providers widgets.
///
/// An [AgentTheme] is optional — without one, widgets derive their look from
/// the ambient Material [Theme]. Add one when you want the chat surface
/// styled independently of the rest of the app.
class AgentTheme extends InheritedWidget {
  /// The theme applied to descendants.
  final AgentThemeData data;

  const AgentTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The nearest [AgentThemeData], or `null` if there is no [AgentTheme]
  /// ancestor.
  static AgentThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AgentTheme>()?.data;
  }

  /// The nearest [AgentThemeData], falling back to one derived from the
  /// ambient Material theme.
  ///
  /// Because the fallback tracks [Theme.of], a kit widget dropped into any
  /// app picks up that app's color scheme and brightness automatically.
  static AgentThemeData of(BuildContext context) {
    return maybeOf(context) ?? AgentThemeData.fromTheme(Theme.of(context));
  }

  /// The motion profile for [context], collapsed to [AgentMotion.none] when
  /// the platform requests reduced motion.
  ///
  /// Widgets should read durations through this rather than
  /// `AgentTheme.of(context).motion` so that "reduce motion" is honored
  /// everywhere without per-widget handling.
  static AgentMotion motionOf(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? AgentMotion.none : of(context).motion;
  }

  @override
  bool updateShouldNotify(AgentTheme oldWidget) => data != oldWidget.data;
}

/// An [AgentTheme] that cross-fades when [data] changes.
///
/// Swapping light to dark mid-conversation snaps every bubble at once, which
/// reads as a glitch. This interpolates the whole token set instead.
class AnimatedAgentTheme extends ImplicitlyAnimatedWidget {
  /// The target theme.
  final AgentThemeData data;

  /// The subtree to theme.
  final Widget child;

  const AnimatedAgentTheme({
    super.key,
    required this.data,
    required this.child,
    super.curve,
    super.duration = const Duration(milliseconds: 300),
    super.onEnd,
  });

  @override
  AnimatedWidgetBaseState<AnimatedAgentTheme> createState() =>
      _AnimatedAgentThemeState();
}

class _AnimatedAgentThemeState
    extends AnimatedWidgetBaseState<AnimatedAgentTheme> {
  _AgentThemeDataTween? _data;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _data = visitor(
      _data,
      widget.data,
      (dynamic value) => _AgentThemeDataTween(begin: value as AgentThemeData),
    ) as _AgentThemeDataTween?;
  }

  @override
  Widget build(BuildContext context) {
    return AgentTheme(
      data: _data!.evaluate(animation),
      child: widget.child,
    );
  }
}

class _AgentThemeDataTween extends Tween<AgentThemeData> {
  _AgentThemeDataTween({super.begin});

  @override
  AgentThemeData lerp(double t) => AgentThemeData.lerp(begin!, end!, t);
}
