import 'package:flutter/material.dart';

/// Text styles used across the kit.
///
/// Styles intentionally leave [TextStyle.color] unset — widgets apply the
/// correct semantic color from `AgentColors` at build time, so the same
/// typography scale works on light, dark and glass surfaces.
@immutable
class AgentTypography {
  /// Primary message body text.
  final TextStyle body;

  /// Slightly smaller body text, used in dense layouts.
  final TextStyle bodySmall;

  /// Emphasized label text: tool names, section headers.
  final TextStyle label;

  /// Small uppercase labels such as `INPUT` / `OUTPUT`.
  final TextStyle overline;

  /// Timestamps, token counts, helper text.
  final TextStyle caption;

  /// Monospaced text inside fenced code blocks.
  final TextStyle code;

  /// Monospaced text for inline `code` spans.
  final TextStyle inlineCode;

  /// Markdown `#` heading.
  final TextStyle heading1;

  /// Markdown `##` heading.
  final TextStyle heading2;

  /// Markdown `###` heading and below.
  final TextStyle heading3;

  const AgentTypography({
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.overline,
    required this.caption,
    required this.code,
    required this.inlineCode,
    required this.heading1,
    required this.heading2,
    required this.heading3,
  });

  /// Monospace family fallbacks that resolve on every platform Flutter
  /// targets. Android has no `Menlo`, iOS/macOS has no `monospace`, and
  /// Windows has neither — listing all of them means code always renders in a
  /// fixed-pitch face instead of silently falling back to the body font.
  static const List<String> monospaceFallback = <String>[
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Courier New',
    'monospace',
  ];

  /// The default typographic scale.
  ///
  /// Pass [fontFamily] to route body text through a brand font while leaving
  /// code spans monospaced.
  factory AgentTypography.standard({String? fontFamily}) {
    TextStyle base(double size, FontWeight weight, double height) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
        );

    const mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: monospaceFallback,
    );

    return AgentTypography(
      body: base(15, FontWeight.w400, 1.45),
      bodySmall: base(13.5, FontWeight.w400, 1.4),
      label: base(13.5, FontWeight.w600, 1.3),
      overline: base(10.5, FontWeight.w700, 1.2).copyWith(letterSpacing: 0.6),
      caption: base(11.5, FontWeight.w400, 1.3),
      code: mono.copyWith(fontSize: 12.5, height: 1.5),
      inlineCode: mono.copyWith(fontSize: 13, height: 1.35),
      heading1: base(20, FontWeight.w700, 1.3),
      heading2: base(17.5, FontWeight.w700, 1.3),
      heading3: base(15.5, FontWeight.w600, 1.3),
    );
  }

  /// Scales every style by [factor].
  ///
  /// Useful for a user-facing "text size" setting; prefer this over
  /// [MediaQuery.textScaler] when you want code blocks to scale in lockstep.
  AgentTypography scaled(double factor) {
    TextStyle s(TextStyle t) =>
        t.copyWith(fontSize: (t.fontSize ?? 14) * factor);
    return AgentTypography(
      body: s(body),
      bodySmall: s(bodySmall),
      label: s(label),
      overline: s(overline),
      caption: s(caption),
      code: s(code),
      inlineCode: s(inlineCode),
      heading1: s(heading1),
      heading2: s(heading2),
      heading3: s(heading3),
    );
  }

  AgentTypography copyWith({
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? label,
    TextStyle? overline,
    TextStyle? caption,
    TextStyle? code,
    TextStyle? inlineCode,
    TextStyle? heading1,
    TextStyle? heading2,
    TextStyle? heading3,
  }) {
    return AgentTypography(
      body: body ?? this.body,
      bodySmall: bodySmall ?? this.bodySmall,
      label: label ?? this.label,
      overline: overline ?? this.overline,
      caption: caption ?? this.caption,
      code: code ?? this.code,
      inlineCode: inlineCode ?? this.inlineCode,
      heading1: heading1 ?? this.heading1,
      heading2: heading2 ?? this.heading2,
      heading3: heading3 ?? this.heading3,
    );
  }

  /// Linearly interpolates between two typographic scales.
  static AgentTypography lerp(
    AgentTypography a,
    AgentTypography b,
    double t,
  ) {
    return AgentTypography(
      body: TextStyle.lerp(a.body, b.body, t)!,
      bodySmall: TextStyle.lerp(a.bodySmall, b.bodySmall, t)!,
      label: TextStyle.lerp(a.label, b.label, t)!,
      overline: TextStyle.lerp(a.overline, b.overline, t)!,
      caption: TextStyle.lerp(a.caption, b.caption, t)!,
      code: TextStyle.lerp(a.code, b.code, t)!,
      inlineCode: TextStyle.lerp(a.inlineCode, b.inlineCode, t)!,
      heading1: TextStyle.lerp(a.heading1, b.heading1, t)!,
      heading2: TextStyle.lerp(a.heading2, b.heading2, t)!,
      heading3: TextStyle.lerp(a.heading3, b.heading3, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentTypography &&
        other.body == body &&
        other.bodySmall == bodySmall &&
        other.label == label &&
        other.overline == overline &&
        other.caption == caption &&
        other.code == code &&
        other.inlineCode == inlineCode &&
        other.heading1 == heading1 &&
        other.heading2 == heading2 &&
        other.heading3 == heading3;
  }

  @override
  int get hashCode => Object.hash(
        body,
        bodySmall,
        label,
        overline,
        caption,
        code,
        inlineCode,
        heading1,
        heading2,
        heading3,
      );
}
