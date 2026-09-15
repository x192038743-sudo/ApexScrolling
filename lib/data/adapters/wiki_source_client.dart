import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';

/// 一个候选维基条目（来自 Wikidata SPARQL）。
class WikiCandidate {
  const WikiCandidate({
    required this.qid,
    required this.label,
    required this.title,
    required this.lang,
    required this.sitelinks,
  });

  final String qid;
  final String label;
  final String title;

  /// 'zh' 或 'en'。
  final String lang;
  final int sitelinks;
}

/// 维基百科取文组件：SPARQL 随机候选 + 条目导语抓取。
///
/// 冷门词条源与中文哲学源都基于它，只是喂不同的 Wikidata 类目。
class WikiSourceClient {
  WikiSourceClient(this._net, {Random? random}) : _rng = random ?? Random();

  final NetClient _net;
  final Random _rng;

  /// 按类目取随机候选；[chineseOnly] 为 true 时只保留有中文条目的候选。
  ///
  /// 一次取回多条（默认 12），调用方自己缓存复用，避免每次出卡都等 SPARQL。
  Future<List<WikiCandidate>> randomCandidates({
    required List<String> classes,
    required int maxSitelinks,
    bool chineseOnly = true,
    int limit = 12,
  }) async {
    if (classes.isEmpty) return const <WikiCandidate>[];
    final String values = classes.map((String qid) => 'wd:$qid').join(' ');
    final String query =
        '''
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
  FILTER(BOUND(?zhTitle) ${chineseOnly ? '' : '|| BOUND(?enTitle)'})
  SERVICE wikibase:label { bd:serviceParam wikibase:language "zh,en". }
}
ORDER BY RAND()
LIMIT $limit
''';
    final Map<String, dynamic> json = await _net.postSparql(
      Uri.parse(Endpoints.wikidataSparql),
      query,
    );
    final Object? bindings =
        (json['results'] as Map<String, dynamic>?)?['bindings'];
    if (bindings is! List) return const <WikiCandidate>[];

    final List<WikiCandidate> candidates = <WikiCandidate>[];
    for (final Object? row in bindings) {
      if (row is! Map) continue;
      final String? zh = _bindingValue(row['zhTitle']);
      final String? en = _bindingValue(row['enTitle']);
      final String? title = zh ?? (chineseOnly ? null : en);
      if (title == null || title.isEmpty) continue;
      final String qid = _bindingValue(row['item'])?.split('/').last ?? '';
      final int count = int.tryParse(_bindingValue(row['count']) ?? '') ?? 0;
      if (count > maxSitelinks) continue;
      candidates.add(
        WikiCandidate(
          qid: qid,
          label: _bindingValue(row['itemLabel']) ?? title,
          title: title,
          lang: zh != null ? 'zh' : 'en',
          sitelinks: count,
        ),
      );
    }
    return candidates;
  }

  /// 抓取条目导语（默认取前 4 段）。
  Future<ExtractedArticle> fetchIntro(
    String title, {
    String lang = 'zh',
    int maxParagraphs = 4,
  }) async {
    final String html = await _net.getText(pageHtmlUri(lang, title));
    return TextCleaner.extractIntro(html, maxParagraphs: maxParagraphs);
  }

  /// 抓取条目 HTML（需要从中取内链时用）。
  Future<String> fetchHtml(String title, {String lang = 'zh'}) =>
      _net.getText(pageHtmlUri(lang, title));

  /// 抽取条目内链（兔子洞入口）。
  List<CardLink> linksFrom(String html, {String lang = 'zh', int limit = 5}) =>
      TextCleaner.extractWikiLinks(html, lang: lang, limit: limit)
          .map(
            (({String label, String title, String lang}) l) =>
                CardLink(label: l.label, title: l.title, lang: l.lang),
          )
          .toList();

  /// 一次取回条目导语 + 内链。
  Future<({ExtractedArticle article, List<CardLink> links})> loadArticle(
    String title, {
    String lang = 'zh',
    int maxParagraphs = 4,
  }) async {
    final String html = await fetchHtml(title, lang: lang);
    return (
      article: TextCleaner.extractIntro(html, maxParagraphs: maxParagraphs),
      links: linksFrom(html, lang: lang),
    );
  }

  /// 从候选池里挑一条（随机打散后取第一条）。
  List<WikiCandidate> shuffled(List<WikiCandidate> candidates) =>
      List<WikiCandidate>.of(candidates)..shuffle(_rng);

  static Uri pageHtmlUri(String lang, String title) {
    final String encoded = Uri.encodeComponent(title.replaceAll(' ', '_'));
    return Uri.parse('${Endpoints.wikipediaApiBase}/$lang/page/$encoded/html');
  }

  static String? _bindingValue(Object? node) {
    if (node is Map && node['value'] is String) {
      return (node['value'] as String).trim();
    }
    return null;
  }
}
