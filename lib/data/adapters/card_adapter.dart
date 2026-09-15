import '../../models/text_card.dart';

/// 每个内容源实现一个 Adapter，统一返回 [TextCard]。
abstract class CardAdapter {
  /// 该源对应的卡片类型。
  CardKind get kind;

  /// 展示名（设置页、署名）。
  String get displayName;

  /// 抓取一张卡片；失败时抛 [SourceException]。
  ///
  /// [preferEnglish] 为 true 时优先给英文内容（SEP、古登堡、英文维基等）；
  /// 为 false 时严格使用中文提供者。没有英文提供者的源（如诗词）忽略该参数。
  Future<TextCard> fetch({bool preferEnglish = false});
}

/// 供测试与调试使用的简单来源标注。
class AdapterAttribution {
  const AdapterAttribution._();

  static const String wikipedia = '维基百科 · CC BY-SA 4.0';
  static const String sep = 'Stanford Encyclopedia of Philosophy';
  static const String wikisource = '维基文库 · CC BY-SA 4.0';
  static const String gutenberg = '古登堡计划 · 公有领域';
  static const String wikihow = 'wikiHow · CC BY-NC-SA 3.0';
  static const String wikibooks = '维基教科书 · CC BY-SA 4.0';
  static const String jinrishici = '今日诗词';
}
