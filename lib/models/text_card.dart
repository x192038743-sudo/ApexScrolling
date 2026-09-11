import 'dart:convert';

/// 卡片类型：对应 v1 的六个内容源。
enum CardKind {
  wikiTerm('wikiTerm', '冷门词条'),
  philosophy('philosophy', '哲学观点'),
  classicExcerpt('classicExcerpt', '经典选段'),
  prose('prose', '短篇小说'),
  howTo('howTo', '实用技能'),
  poetry('poetry', '诗词名句');

  const CardKind(this.id, this.label);

  final String id;

  /// 设置页展示用的中文名。
  final String label;

  static CardKind fromId(String id) {
    for (final kind in CardKind.values) {
      if (kind.id == id) return kind;
    }
    return CardKind.wikiTerm;
  }
}

/// 词条卡内可点击的维基内链（兔子洞入口）。
class CardLink {
  const CardLink({required this.label, required this.title, this.lang = 'zh'});

  /// 显示文本。
  final String label;

  /// 目标条目名（用于再次拉取摘要）。
  final String title;

  /// 目标语言版本。
  final String lang;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'label': label, 'title': title, 'lang': lang};

  static CardLink fromJson(Map<String, dynamic> json) => CardLink(
        label: json['label'] as String? ?? '',
        title: json['title'] as String? ?? '',
        lang: json['lang'] as String? ?? 'zh',
      );
}

/// 信息流中的一张纯文字卡片。
class TextCard {
  const TextCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.attribution,
    this.subtitle,
    this.steps = const <String>[],
    this.sourceUrl,
    this.links = const <CardLink>[],
    this.depth = 0,
    required this.fetchedAt,
  });

  /// 去重用的稳定标识（同一内容不重复出现在一次会话里）。
  final String id;
  final CardKind kind;

  /// 卡片顶部粗体标题。
  final String title;

  /// 标题下方的小字来源署名（如「维基百科 · 中文」）。
  final String? subtitle;

  /// 正文（卡片态与展开态共用）。
  final String body;

  /// 步骤化内容（wikiHow 编号步骤卡）。
  final List<String> steps;

  /// 底部署名 / 授权说明。
  final String attribution;

  /// 原文链接，仅用于设置页或分享，卡片内不展示。
  final String? sourceUrl;

  /// 词条内链。
  final List<CardLink> links;

  /// 兔子洞深度：0 为信息流原生卡片，最大 5。
  final int depth;

  final DateTime fetchedAt;

  static const int maxDepth = 5;

  bool get canDigDeeper => depth < maxDepth && links.isNotEmpty;

  /// 展开态渲染的完整正文（步骤卡合成编号步骤）。
  String get fullText {
    if (steps.isEmpty) return body;
    final buffer = StringBuffer(body.trimRight());
    for (var i = 0; i < steps.length; i++) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('${i + 1}. ${steps[i]}');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.id,
        'title': title,
        'subtitle': subtitle,
        'body': body,
        'steps': steps,
        'attribution': attribution,
        'sourceUrl': sourceUrl,
        'links': links.map((CardLink l) => l.toJson()).toList(),
        'depth': depth,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static TextCard fromJson(Map<String, dynamic> json) => TextCard(
        id: json['id'] as String? ?? '',
        kind: CardKind.fromId(json['kind'] as String? ?? 'wikiTerm'),
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
        body: json['body'] as String? ?? '',
        steps: (json['steps'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
        attribution: json['attribution'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String?,
        links: (json['links'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(CardLink.fromJson)
            .toList(),
        depth: json['depth'] as int? ?? 0,
        fetchedAt:
            DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );

  String encode() => jsonEncode(toJson());

  static TextCard decode(String raw) =>
      TextCard.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
