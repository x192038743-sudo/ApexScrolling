import 'text_card.dart';

/// 主题：默认跟随系统，可手动覆盖（计划书要求）。
enum AppThemeOption {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeOption(this.id, this.label);

  final String id;
  final String label;

  static AppThemeOption fromId(String id) => AppThemeOption.values.firstWhere(
    (AppThemeOption o) => o.id == id,
    orElse: () => AppThemeOption.system,
  );
}

/// 词条「冷门」档位：站点链接数阈值。
enum WikiRarity {
  loose(100, '宽松'),
  strict(20, '严格');

  const WikiRarity(this.maxSitelinks, this.label);

  /// 允许的最大站点链接数（越少越冷门）。
  final int maxSitelinks;
  final String label;

  static WikiRarity fromId(String id) => WikiRarity.values.firstWhere(
    (WikiRarity r) => r.name == id,
    orElse: () => WikiRarity.loose,
  );
}

/// 本地设置（无账号、无云端，全部存 SharedPreferences）。
class AppSettings {
  const AppSettings({
    this.enabledSources = const <CardKind>{
      CardKind.wikiTerm,
      CardKind.philosophy,
      CardKind.classicExcerpt,
      CardKind.prose,
      CardKind.howTo,
      CardKind.poetry,
    },
    this.fontScaleLevel = 1,
    this.theme = AppThemeOption.system,
    this.wikiRarity = WikiRarity.loose,
    this.englishPercent = 20,
  });

  /// 已启用的内容源（设置中逐源开关）。
  final Set<CardKind> enabledSources;

  /// 字号三档：0 小 / 1 标准 / 2 大。
  final int fontScaleLevel;

  final AppThemeOption theme;
  final WikiRarity wikiRarity;

  /// 英文内容推送占比（0–100，步进 10，默认 20）。
  ///
  /// 每张卡片按该概率选择英文提供者；诗词源只有中文，因此实际英文占比
  /// 约为设定值 × 5/6。
  final int englishPercent;

  /// 滑块档位（0,10,…,100）。
  static const List<int> englishPercentStops = <int>[
    0,
    10,
    20,
    30,
    40,
    50,
    60,
    70,
    80,
    90,
    100,
  ];

  static const List<double> fontScales = <double>[0.9, 1.0, 1.14];

  double get fontScale =>
      fontScales[fontScaleLevel.clamp(0, fontScales.length - 1)];

  bool isEnabled(CardKind kind) => enabledSources.contains(kind);

  AppSettings copyWith({
    Set<CardKind>? enabledSources,
    int? fontScaleLevel,
    AppThemeOption? theme,
    WikiRarity? wikiRarity,
    int? englishPercent,
  }) => AppSettings(
    enabledSources: enabledSources ?? this.enabledSources,
    fontScaleLevel: fontScaleLevel ?? this.fontScaleLevel,
    theme: theme ?? this.theme,
    wikiRarity: wikiRarity ?? this.wikiRarity,
    englishPercent: englishPercent ?? this.englishPercent,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabledSources': enabledSources
        .map((CardKind k) => k.id)
        .toList(growable: false),
    'fontScaleLevel': fontScaleLevel,
    'theme': theme.id,
    'wikiRarity': wikiRarity.name,
    'englishPercent': englishPercent,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final List<dynamic>? sources = json['enabledSources'] as List<dynamic>?;
    return AppSettings(
      enabledSources: sources == null
          ? const AppSettings().enabledSources
          : sources.map((dynamic e) => CardKind.fromId(e.toString())).toSet(),
      fontScaleLevel: json['fontScaleLevel'] as int? ?? 1,
      theme: AppThemeOption.fromId(json['theme'] as String? ?? 'system'),
      wikiRarity: WikiRarity.fromId(json['wikiRarity'] as String? ?? 'loose'),
      // 旧版本设置里没有这个字段，取默认 20%。
      englishPercent: (json['englishPercent'] as int? ?? 20).clamp(0, 100),
    );
  }
}
