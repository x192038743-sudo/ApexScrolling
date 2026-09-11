import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/app_settings.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';

/// 单个候选词条（来自 Wikidata）。
class _WikiCandidate {
  const _WikiCandidate({
    required this.qid,
    required this.label,
    required this.title,
    required this.lang,
    required this.sitelinks,
  });

  final String qid;
  final String label;
  final String title;
  final String lang;
  final int sitelinks;
}

/// 冷门学术词条：Wikidata SPARQL 限定学科领域 + 站点链接数阈值，
/// 再取维基百科条目导语。
class WikiTermAdapter implements CardAdapter {
  WikiTermAdapter(this._net, this._settings, {Random? random})
      : _rng = random ?? Random();

  final NetClient _net;
  final AppSettings _settings;
  final Random _rng;

  /// 候选池：一次 SPARQL 查询（较慢）取回多条候选，
  /// 之后若干张词条卡可直接复用，显著降低连续出卡的延迟。
  final List<_WikiCandidate> _pool = <_WikiCandidate>[];

  /// 学术领域类目：经 Wikidata 普查，均为「实例数足够 + 中文条目齐全」的类。
  static const List<String> academicClasses = <String>[
    'Q11862829', // 学科
    'Q1969448', // 术语
    'Q65943', // 定理
    'Q24034552', // 数学概念
    'Q33104279', // 哲学概念
    'Q483372', // 悖论
    'Q5389993', // 哲学立场
    'Q147027', // 思想实验
    'Q33104129', // 社会学概念
    'Q66664364', // 语言学概念
    'Q33104303', // 物理学概念
    'Q179805', // 政治哲学
  ];

  @override
  CardKind get kind => CardKind.wikiTerm;

  @override
  String get displayName => '冷门学术词条';

  @override
  Future<TextCard> fetch() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final _WikiCandidate? candidate = await _nextCandidate();
      if (candidate == null) break;
      try {
        final TextCard card = await fetchByTitle(
          candidate.title,
          lang: candidate.lang,
          subtitleLabel: candidate.label,
        );
        if (card.body.length >= 80) return card;
      } on SourceException catch (error) {
        lastError = error;
      }
    }
    throw SourceException(
      lastError == null ? 'Wikidata 未返回候选词条' : '候选词条均无法解析：$lastError',
    );
  }

  /// 从候选池取一条；池空时补货。
  Future<_WikiCandidate?> _nextCandidate() async {
    while (_pool.isNotEmpty) {
      final _WikiCandidate candidate = _pool.removeAt(0);
      if (candidate.sitelinks > _settings.wikiRarity.maxSitelinks) continue;
      return candidate;
    }
    final List<_WikiCandidate> fetched = await _queryCandidates();
    _pool
      ..clear()
      ..addAll(fetched.where((_WikiCandidate c) =>
          c.sitelinks <= _settings.wikiRarity.maxSitelinks))
      ..shuffle(_rng);
    if (_pool.isEmpty) return null;
    return _pool.removeAt(0);
  }

  /// 供「兔子洞」使用：按条目名直接抓一张卡片。
  Future<TextCard> fetchByTitle(
    String title, {
    String lang = 'zh',
    String? subtitleLabel,
    int depth = 0,
  }) async {
    final String html = await _net.getText(_pageHtmlUri(lang, title));
    final ExtractedArticle article =
        TextCleaner.extractIntro(html, maxParagraphs: 4);
    final String body = article.body;
    if (body.length < 60) {
      throw SourceException('条目正文过短：$title');
    }
    final String displayTitle = article.title.isNotEmpty
        ? article.title
        : (subtitleLabel?.isNotEmpty == true ? subtitleLabel! : title);
    final List<({String label, String title, String lang})> rawLinks =
        TextCleaner.extractWikiLinks(html, lang: lang, limit: 5);
    return TextCard(
      id: 'wiki:$lang:${title.replaceAll(' ', '_')}',
      kind: kind,
      title: displayTitle,
      subtitle: lang == 'zh' ? '维基百科 · 中文' : '维基百科 · 英文',
      body: body,
      attribution: AdapterAttribution.wikipedia,
      sourceUrl: 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      links: rawLinks
          .map((({String label, String title, String lang}) l) =>
              CardLink(label: l.label, title: l.title, lang: l.lang))
          .toList(),
      depth: depth,
      fetchedAt: DateTime.now(),
    );
  }

  /// Wikidata 随机候选：按领域类目过滤 + 站点链接数 ≤ 阈值。
  Future<List<_WikiCandidate>> _queryCandidates() async {
    final int maxSitelinks = _settings.wikiRarity.maxSitelinks;
    final String values = academicClasses
        .map((String qid) => 'wd:$qid')
        .join(' ');
    final String query = '''
SELECT ?item ?itemLabel ?count ?zhTitle ?enTitle WHERE {
  VALUES ?cls { $values }
  ?item wdt:P31 ?cls .
  ?item wikibase:sitelinks ?count .
  FILTER(?count <= $maxSitelinks && ?count >= 2)
  OPTIONAL {
    ?zhArticle schema:about ?item ;
               schema:isPartOf <https://zh.wikipedia.org/> ;
               schema:name ?zhTitle .
  }
  OPTIONAL {
    ?enArticle schema:about ?item ;
               schema:isPartOf <https://en.wikipedia.org/> ;
               schema:name ?enTitle .
  }
  FILTER(BOUND(?zhTitle) || BOUND(?enTitle))
  SERVICE wikibase:label { bd:serviceParam wikibase:language "zh,en". }
}
ORDER BY RAND()
LIMIT 12
''';
    final Map<String, dynamic> json = await _net.postSparql(
      Uri.parse(Endpoints.wikidataSparql),
      query,
    );
    final Object? bindings =
        (json['results'] as Map<String, dynamic>?)?['bindings'];
    if (bindings is! List) return const <_WikiCandidate>[];

    final List<_WikiCandidate> candidates = <_WikiCandidate>[];
    for (final Object? row in bindings) {
      if (row is! Map) continue;
      final String? zh = _bindingValue(row['zhTitle']);
      final String? en = _bindingValue(row['enTitle']);
      final String? title = zh ?? en;
      if (title == null || title.isEmpty) continue;
      final String qid = _bindingValue(row['item'])
              ?.split('/')
              .last ??
          '';
      final int count =
          int.tryParse(_bindingValue(row['count']) ?? '') ?? 0;
      final String label = _bindingValue(row['itemLabel']) ?? title;
      candidates.add(_WikiCandidate(
        qid: qid,
        label: label,
        title: title,
        lang: zh != null ? 'zh' : 'en',
        sitelinks: count,
      ));
    }
    return candidates;
  }

  static String? _bindingValue(Object? node) {
    if (node is Map && node['value'] is String) {
      return (node['value'] as String).trim();
    }
    return null;
  }

  static Uri _pageHtmlUri(String lang, String title) {
    final String encoded =
        Uri.encodeComponent(title.replaceAll(' ', '_'));
    return Uri.parse(
      '${Endpoints.wikipediaApiBase}/$lang/page/$encoded/html',
    );
  }
}
