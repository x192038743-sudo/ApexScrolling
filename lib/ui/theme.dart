import 'package:flutter/material.dart';

/// 配色：深色为默认沉浸底色，浅色为「纸感」阅读底色。
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color accent;
  final Color divider;

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0F0F11),
    surface: Color(0xFF17171A),
    text: Color(0xFFEDEAE3),
    muted: Color(0xFF8B867D),
    accent: Color(0xFFC9A227),
    divider: Color(0x1FFFFFFF),
  );

  static const AppPalette light = AppPalette(
    background: Color(0xFFFAF7F1),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1C1A17),
    muted: Color(0xFF6E6961),
    accent: Color(0xFF8C6D1F),
    divider: Color(0x1A000000),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 排版：默认衬线（中文思源宋体/霞鹜文楷回退链，英文 Georgia），
/// 行距 1.8+，字号三档可调。
class AppTextStyles {
  const AppTextStyles._();

  /// 中文衬线回退链：iOS/macOS → Android → Windows。
  static const List<String> serifFallback = <String>[
    'LXGW WenKai',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Source Han Serif SC',
    'Source Han Serif CN',
    'Songti SC',
    'STSong',
    'SimSun',
    'Times New Roman',
    'serif',
  ];

  static const String serifLatin = 'Georgia';

  static TextStyle title(double scale, AppPalette palette) => TextStyle(
        fontFamily: serifLatin,
        fontFamilyFallback: serifFallback,
        fontSize: 27 * scale,
        height: 1.28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: palette.text,
      );

  static TextStyle body(double scale, AppPalette palette) => TextStyle(
        fontFamily: serifLatin,
        fontFamilyFallback: serifFallback,
        fontSize: 18 * scale,
        height: 1.85,
        letterSpacing: 0.3,
        color: palette.text,
      );

  static TextStyle meta(double scale, AppPalette palette) => TextStyle(
        fontFamily: serifLatin,
        fontFamilyFallback: serifFallback,
        fontSize: 12.5 * (0.94 + 0.06 * scale),
        height: 1.5,
        letterSpacing: 0.5,
        color: palette.muted,
      );

  static TextStyle link(double scale, AppPalette palette) => TextStyle(
        fontFamily: serifLatin,
        fontFamilyFallback: serifFallback,
        fontSize: 16 * scale,
        height: 1.6,
        color: palette.text,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: palette.muted,
      );
}

/// 主题构建：Material 3 + 极简底色（卡片内不出现任何装饰元素）。
class AppTheme {
  const AppTheme._();

  static ThemeData build(Brightness brightness) {
    final AppPalette palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    ).copyWith(
      surface: palette.background,
      onSurface: palette.text,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.text,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: AppTextStyles.serifLatin,
          fontFamilyFallback: AppTextStyles.serifFallback,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      dividerColor: palette.divider,
      textTheme: Typography.material2021(
        platform: TargetPlatform.android,
      ).white.apply(
            fontFamily: AppTextStyles.serifLatin,
            fontFamilyFallback: AppTextStyles.serifFallback,
            bodyColor: palette.text,
            displayColor: palette.text,
          ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.background
              : palette.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.accent
              : palette.muted.withValues(alpha: 0.3),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(
            fontFamily: AppTextStyles.serifLatin,
            fontFamilyFallback: AppTextStyles.serifFallback,
            fontSize: 14,
          )),
          foregroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? palette.background
                : palette.text,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? palette.accent
                : Colors.transparent,
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: palette.divider),
          ),
        ),
      ),
    );
  }
}
