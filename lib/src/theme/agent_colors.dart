import 'package:flutter/material.dart';

/// Syntax highlighting colors used by fenced code blocks.
///
/// Kept separate from [AgentColors] so that swapping a code theme does not
/// require respecifying the entire surface palette.
@immutable
class AgentSyntaxColors {
  /// Language keywords (`class`, `return`, `async`, ...).
  final Color keyword;

  /// String and character literals.
  final Color string;

  /// Numeric literals.
  final Color number;

  /// Line and block comments.
  final Color comment;

  /// Function and method names at call/declaration sites.
  final Color function;

  /// Type names and class identifiers.
  final Color type;

  /// Brackets, operators and separators.
  final Color punctuation;

  /// Plain identifiers and anything not otherwise classified.
  final Color plain;

  const AgentSyntaxColors({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.function,
    required this.type,
    required this.punctuation,
    required this.plain,
  });

  /// Palette tuned for light code surfaces.
  factory AgentSyntaxColors.light() => const AgentSyntaxColors(
        keyword: Color(0xFF9333EA),
        string: Color(0xFF15803D),
        number: Color(0xFFC2410C),
        comment: Color(0xFF94A3B8),
        function: Color(0xFF2563EB),
        type: Color(0xFF0891B2),
        punctuation: Color(0xFF64748B),
        plain: Color(0xFF1E293B),
      );

  /// Palette tuned for dark code surfaces.
  factory AgentSyntaxColors.dark() => const AgentSyntaxColors(
        keyword: Color(0xFFC084FC),
        string: Color(0xFF86EFAC),
        number: Color(0xFFFDBA74),
        comment: Color(0xFF64748B),
        function: Color(0xFF7DD3FC),
        type: Color(0xFF67E8F9),
        punctuation: Color(0xFF94A3B8),
        plain: Color(0xFFE2E8F0),
      );

  AgentSyntaxColors copyWith({
    Color? keyword,
    Color? string,
    Color? number,
    Color? comment,
    Color? function,
    Color? type,
    Color? punctuation,
    Color? plain,
  }) {
    return AgentSyntaxColors(
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      comment: comment ?? this.comment,
      function: function ?? this.function,
      type: type ?? this.type,
      punctuation: punctuation ?? this.punctuation,
      plain: plain ?? this.plain,
    );
  }

  /// Linearly interpolates between two syntax palettes.
  static AgentSyntaxColors lerp(
    AgentSyntaxColors a,
    AgentSyntaxColors b,
    double t,
  ) {
    return AgentSyntaxColors(
      keyword: Color.lerp(a.keyword, b.keyword, t)!,
      string: Color.lerp(a.string, b.string, t)!,
      number: Color.lerp(a.number, b.number, t)!,
      comment: Color.lerp(a.comment, b.comment, t)!,
      function: Color.lerp(a.function, b.function, t)!,
      type: Color.lerp(a.type, b.type, t)!,
      punctuation: Color.lerp(a.punctuation, b.punctuation, t)!,
      plain: Color.lerp(a.plain, b.plain, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentSyntaxColors &&
        other.keyword == keyword &&
        other.string == string &&
        other.number == number &&
        other.comment == comment &&
        other.function == function &&
        other.type == type &&
        other.punctuation == punctuation &&
        other.plain == plain;
  }

  @override
  int get hashCode => Object.hash(
        keyword,
        string,
        number,
        comment,
        function,
        type,
        punctuation,
        plain,
      );
}

/// The semantic color palette for every widget in agent_ui_kit_providers.
///
/// Colors are semantic rather than literal — widgets ask for
/// [assistantBubble] or [toolBorder], never for "grey 200". That indirection
/// is what lets [AgentColors.light], [AgentColors.dark] and
/// [AgentColors.glass] restyle the whole kit without touching widget code.
@immutable
class AgentColors {
  /// The page background behind the message list.
  final Color surface;

  /// Background for raised containers: input bar, tool cards, sheets.
  final Color surfaceContainer;

  /// A slightly stronger container used for hover/pressed states.
  final Color surfaceContainerHigh;

  /// Fill of the user's own message bubble.
  final Color userBubble;

  /// Text/icon color inside [userBubble].
  final Color onUserBubble;

  /// Fill of the assistant's message bubble.
  final Color assistantBubble;

  /// Text/icon color inside [assistantBubble].
  final Color onAssistantBubble;

  /// Fill of system/notice bubbles.
  final Color systemBubble;

  /// Text/icon color inside [systemBubble].
  final Color onSystemBubble;

  /// Primary brand color: send button, active states, focus rings.
  final Color accent;

  /// Text/icon color drawn on top of [accent].
  final Color onAccent;

  /// A low-opacity tint of [accent] for chips and subtle backgrounds.
  final Color accentSubtle;

  /// Highest-emphasis body text.
  final Color textPrimary;

  /// Supporting text: timestamps, captions, labels.
  final Color textSecondary;

  /// Lowest-emphasis text: placeholders, disabled states.
  final Color textTertiary;

  /// Default hairline border.
  final Color border;

  /// A heavier border for focused or selected elements.
  final Color borderStrong;

  /// Background of a [ToolCallCard].
  final Color toolSurface;

  /// Border of a [ToolCallCard].
  final Color toolBorder;

  /// Success state (tool succeeded, message delivered).
  final Color success;

  /// Warning state.
  final Color warning;

  /// Error state (tool failed, send failed).
  final Color error;

  /// Informational state.
  final Color info;

  /// Background of fenced code blocks.
  final Color codeSurface;

  /// Border of fenced code blocks.
  final Color codeBorder;

  /// Background of inline `code` spans.
  final Color inlineCodeSurface;

  /// Scrim used behind modals and image viewers.
  final Color overlay;

  /// Foreground for content drawn on top of [textPrimary] used as a fill.
  ///
  /// Badges like the attachment remove button invert the surface — a
  /// [textPrimary] circle with a small glyph on it. [surface] cannot serve as
  /// that glyph color, because a translucent theme sets it to
  /// [Colors.transparent] and the glyph disappears.
  final Color onInverseSurface;

  /// Syntax highlighting palette for fenced code blocks.
  final AgentSyntaxColors syntax;

  const AgentColors({
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.userBubble,
    required this.onUserBubble,
    required this.assistantBubble,
    required this.onAssistantBubble,
    required this.systemBubble,
    required this.onSystemBubble,
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.toolSurface,
    required this.toolBorder,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.codeSurface,
    required this.codeBorder,
    required this.inlineCodeSurface,
    required this.overlay,
    required this.onInverseSurface,
    required this.syntax,
  });

  /// The default light palette.
  factory AgentColors.light({Color accent = const Color(0xFF6C5CE7)}) {
    return AgentColors(
      surface: const Color(0xFFFFFFFF),
      surfaceContainer: const Color(0xFFF8F8FB),
      surfaceContainerHigh: const Color(0xFFF1F1F6),
      userBubble: accent,
      onUserBubble: Colors.white,
      assistantBubble: const Color(0xFFF3F3F7),
      onAssistantBubble: const Color(0xFF16161A),
      systemBubble: const Color(0xFFFFF7ED),
      onSystemBubble: const Color(0xFF7C2D12),
      accent: accent,
      onAccent: Colors.white,
      accentSubtle: accent.withValues(alpha: 0.10),
      textPrimary: const Color(0xFF16161A),
      textSecondary: const Color(0xFF5C5C6B),
      textTertiary: const Color(0xFF9B9BA5),
      border: const Color(0xFFE4E4EB),
      borderStrong: const Color(0xFFC9C9D4),
      toolSurface: const Color(0xFFFAFAFC),
      toolBorder: const Color(0xFFE4E4EB),
      success: const Color(0xFF16A34A),
      warning: const Color(0xFFD97706),
      error: const Color(0xFFDC2626),
      info: const Color(0xFF2563EB),
      codeSurface: const Color(0xFFF6F6F9),
      codeBorder: const Color(0xFFE4E4EB),
      inlineCodeSurface: const Color(0xFFEFEFF4),
      overlay: Colors.black.withValues(alpha: 0.45),
      onInverseSurface: const Color(0xFFFFFFFF),
      syntax: AgentSyntaxColors.light(),
    );
  }

  /// The default dark palette.
  factory AgentColors.dark({Color accent = const Color(0xFF8B7CF6)}) {
    return AgentColors(
      surface: const Color(0xFF0E0E12),
      surfaceContainer: const Color(0xFF17171D),
      surfaceContainerHigh: const Color(0xFF1F1F27),
      userBubble: accent,
      onUserBubble: Colors.white,
      assistantBubble: const Color(0xFF1C1C24),
      onAssistantBubble: const Color(0xFFECECF1),
      systemBubble: const Color(0xFF2A1F14),
      onSystemBubble: const Color(0xFFFDBA74),
      accent: accent,
      onAccent: Colors.white,
      accentSubtle: accent.withValues(alpha: 0.18),
      textPrimary: const Color(0xFFECECF1),
      textSecondary: const Color(0xFFA1A1B0),
      textTertiary: const Color(0xFF6B6B7B),
      border: const Color(0xFF2A2A34),
      borderStrong: const Color(0xFF3D3D4A),
      toolSurface: const Color(0xFF17171D),
      toolBorder: const Color(0xFF2A2A34),
      success: const Color(0xFF4ADE80),
      warning: const Color(0xFFFBBF24),
      error: const Color(0xFFF87171),
      info: const Color(0xFF60A5FA),
      codeSurface: const Color(0xFF12121A),
      codeBorder: const Color(0xFF2A2A34),
      inlineCodeSurface: const Color(0xFF24242E),
      overlay: Colors.black.withValues(alpha: 0.65),
      onInverseSurface: const Color(0xFF0E0E12),
      syntax: AgentSyntaxColors.dark(),
    );
  }

  /// A translucent palette intended to sit on top of a gradient or image.
  ///
  /// Pair with a blurred backdrop — see `AgentThemeData.glass`.
  factory AgentColors.glass({Color accent = const Color(0xFF8B7CF6)}) {
    return AgentColors(
      surface: Colors.transparent,
      surfaceContainer: Colors.white.withValues(alpha: 0.06),
      surfaceContainerHigh: Colors.white.withValues(alpha: 0.12),
      userBubble: accent.withValues(alpha: 0.85),
      onUserBubble: Colors.white,
      assistantBubble: Colors.white.withValues(alpha: 0.08),
      onAssistantBubble: Colors.white.withValues(alpha: 0.92),
      systemBubble: Colors.amber.withValues(alpha: 0.12),
      onSystemBubble: const Color(0xFFFDE68A),
      accent: accent,
      onAccent: Colors.white,
      accentSubtle: accent.withValues(alpha: 0.20),
      textPrimary: Colors.white.withValues(alpha: 0.95),
      textSecondary: Colors.white.withValues(alpha: 0.70),
      textTertiary: Colors.white.withValues(alpha: 0.45),
      border: Colors.white.withValues(alpha: 0.15),
      borderStrong: Colors.white.withValues(alpha: 0.28),
      toolSurface: Colors.white.withValues(alpha: 0.06),
      toolBorder: Colors.white.withValues(alpha: 0.15),
      success: const Color(0xFF4ADE80),
      warning: const Color(0xFFFBBF24),
      error: const Color(0xFFF87171),
      info: const Color(0xFF60A5FA),
      codeSurface: Colors.black.withValues(alpha: 0.28),
      codeBorder: Colors.white.withValues(alpha: 0.12),
      inlineCodeSurface: Colors.white.withValues(alpha: 0.12),
      overlay: Colors.black.withValues(alpha: 0.55),
      onInverseSurface: const Color(0xFF12121A),
      syntax: AgentSyntaxColors.dark(),
    );
  }

  /// Derives a palette from an existing Material [ColorScheme].
  ///
  /// Use this when the host app already has a brand theme and you want the
  /// chat surface to inherit it rather than define its own.
  factory AgentColors.fromColorScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final base = isDark
        ? AgentColors.dark(accent: scheme.primary)
        : AgentColors.light(accent: scheme.primary);

    return base.copyWith(
      surface: scheme.surface,
      surfaceContainer: scheme.surfaceContainerLow,
      surfaceContainerHigh: scheme.surfaceContainerHigh,
      userBubble: scheme.primary,
      onUserBubble: scheme.onPrimary,
      assistantBubble: scheme.surfaceContainerHighest,
      onAssistantBubble: scheme.onSurface,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      accentSubtle: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      border: scheme.outlineVariant,
      borderStrong: scheme.outline,
      error: scheme.error,
    );
  }

  AgentColors copyWith({
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? userBubble,
    Color? onUserBubble,
    Color? assistantBubble,
    Color? onAssistantBubble,
    Color? systemBubble,
    Color? onSystemBubble,
    Color? accent,
    Color? onAccent,
    Color? accentSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? toolSurface,
    Color? toolBorder,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? codeSurface,
    Color? codeBorder,
    Color? inlineCodeSurface,
    Color? overlay,
    Color? onInverseSurface,
    AgentSyntaxColors? syntax,
  }) {
    return AgentColors(
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      userBubble: userBubble ?? this.userBubble,
      onUserBubble: onUserBubble ?? this.onUserBubble,
      assistantBubble: assistantBubble ?? this.assistantBubble,
      onAssistantBubble: onAssistantBubble ?? this.onAssistantBubble,
      systemBubble: systemBubble ?? this.systemBubble,
      onSystemBubble: onSystemBubble ?? this.onSystemBubble,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      toolSurface: toolSurface ?? this.toolSurface,
      toolBorder: toolBorder ?? this.toolBorder,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      codeSurface: codeSurface ?? this.codeSurface,
      codeBorder: codeBorder ?? this.codeBorder,
      inlineCodeSurface: inlineCodeSurface ?? this.inlineCodeSurface,
      overlay: overlay ?? this.overlay,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      syntax: syntax ?? this.syntax,
    );
  }

  /// Linearly interpolates between two palettes, enabling animated theme
  /// transitions (see `AnimatedAgentTheme`).
  static AgentColors lerp(AgentColors a, AgentColors b, double t) {
    return AgentColors(
      surface: Color.lerp(a.surface, b.surface, t)!,
      surfaceContainer: Color.lerp(a.surfaceContainer, b.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(a.surfaceContainerHigh, b.surfaceContainerHigh, t)!,
      userBubble: Color.lerp(a.userBubble, b.userBubble, t)!,
      onUserBubble: Color.lerp(a.onUserBubble, b.onUserBubble, t)!,
      assistantBubble: Color.lerp(a.assistantBubble, b.assistantBubble, t)!,
      onAssistantBubble:
          Color.lerp(a.onAssistantBubble, b.onAssistantBubble, t)!,
      systemBubble: Color.lerp(a.systemBubble, b.systemBubble, t)!,
      onSystemBubble: Color.lerp(a.onSystemBubble, b.onSystemBubble, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
      accentSubtle: Color.lerp(a.accentSubtle, b.accentSubtle, t)!,
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
      textTertiary: Color.lerp(a.textTertiary, b.textTertiary, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
      toolSurface: Color.lerp(a.toolSurface, b.toolSurface, t)!,
      toolBorder: Color.lerp(a.toolBorder, b.toolBorder, t)!,
      success: Color.lerp(a.success, b.success, t)!,
      warning: Color.lerp(a.warning, b.warning, t)!,
      error: Color.lerp(a.error, b.error, t)!,
      info: Color.lerp(a.info, b.info, t)!,
      codeSurface: Color.lerp(a.codeSurface, b.codeSurface, t)!,
      codeBorder: Color.lerp(a.codeBorder, b.codeBorder, t)!,
      inlineCodeSurface:
          Color.lerp(a.inlineCodeSurface, b.inlineCodeSurface, t)!,
      overlay: Color.lerp(a.overlay, b.overlay, t)!,
      onInverseSurface:
          Color.lerp(a.onInverseSurface, b.onInverseSurface, t)!,
      syntax: AgentSyntaxColors.lerp(a.syntax, b.syntax, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentColors &&
        other.surface == surface &&
        other.surfaceContainer == surfaceContainer &&
        other.surfaceContainerHigh == surfaceContainerHigh &&
        other.userBubble == userBubble &&
        other.onUserBubble == onUserBubble &&
        other.assistantBubble == assistantBubble &&
        other.onAssistantBubble == onAssistantBubble &&
        other.systemBubble == systemBubble &&
        other.onSystemBubble == onSystemBubble &&
        other.accent == accent &&
        other.onAccent == onAccent &&
        other.accentSubtle == accentSubtle &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textTertiary == textTertiary &&
        other.border == border &&
        other.borderStrong == borderStrong &&
        other.toolSurface == toolSurface &&
        other.toolBorder == toolBorder &&
        other.success == success &&
        other.warning == warning &&
        other.error == error &&
        other.info == info &&
        other.codeSurface == codeSurface &&
        other.codeBorder == codeBorder &&
        other.inlineCodeSurface == inlineCodeSurface &&
        other.overlay == overlay &&
        other.onInverseSurface == onInverseSurface &&
        other.syntax == syntax;
  }

  @override
  int get hashCode => Object.hashAll([
        surface,
        surfaceContainer,
        surfaceContainerHigh,
        userBubble,
        onUserBubble,
        assistantBubble,
        onAssistantBubble,
        systemBubble,
        onSystemBubble,
        accent,
        onAccent,
        accentSubtle,
        textPrimary,
        textSecondary,
        textTertiary,
        border,
        borderStrong,
        toolSurface,
        toolBorder,
        success,
        warning,
        error,
        info,
        codeSurface,
        codeBorder,
        inlineCodeSurface,
        overlay,
        onInverseSurface,
        syntax,
      ]);
}
