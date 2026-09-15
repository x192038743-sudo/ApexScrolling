import 'dart:math';

import '../../models/app_settings.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'wiki_source_client.dart';

/// 冷门学术词条：Wikidata SPARQL 限定学科领域 + 站点链接数阈值，
/// 再取维基百科条目导语。
///
/// 哲学四类（哲学概念/哲学立场/悖论/思想实验）划给「哲学观点」源，
/// 这里只保留其余学术类目，避免两个源内容重叠。
class WikiTermAdapter implements CardAdapter {
  WikiTermAdapter(
    NetClient net,
    this._settings, {
    Random? random,
    WikiSourceClient? wikiSource,
  }) : _wiki = wikiSource ?? WikiSourceClient(net, random: random);

  final AppSettings _settings;
  final WikiSourceClient _wiki;

  /// 学术领域类目：经 Wikidata 普查，均为「实例数足够 + 中文条目齐全」的类。
  static const List<String> academicClasses = <String>[
    'Q11862829', // 学科
    'Q1969448', // 术语
    'Q65943', // 定理
    'Q24034552', // 数学概念
    'Q33104129', // 社会学概念
    'Q66664364', // 语言学概念
    'Q33104303', // 物理学概念
  ];

  /// 候选池：一次 SPARQL（较慢）取回多条，之后若干张卡直接复用。
  final List<WikiCandidate> _pool = <WikiCandidate>[];

  /// 会话内已出过的条目，避免短时间内重复。
  final List<String> _recent = <String>[];
  static const int _recentWindow = 16;

  @override
  CardKind get kind => CardKind.wikiTerm;

  @override
  String get displayName => '冷门学术词条';

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final WikiCandidate? candidate = await _nextCandidate(
        // 关掉英文时只取有中文条目的候选；开启英文时允许无中文的条目。
        chineseOnly: !preferEnglish,
      );
      if (candidate == null) break;
      try {
        final TextCard card = await fetchByTitle(
          candidate.title,
          lang: candidate.lang,
          subtitleLabel: candidate.label,
        );
        if (card.body.length >= 80) {
          _remember(candidate.title);
          return card;
        }
      } on SourceException catch (error) {
        lastError = error;
      }
    }
    throw SourceException(
      lastError == null ? 'Wikidata 未返回候选词条' : '候选词条均无法解析：$lastError',
    );
  }

  /// 供「兔子洞」使用：按条目名直接抓一张卡片。
  Future<TextCard> fetchByTitle(
    String title, {
    String lang = 'zh',
    String? subtitleLabel,
    int depth = 0,
  }) async {
    final ({ExtractedArticle article, List<CardLink> links}) loaded =
        await _wiki.loadArticle(title, lang: lang, maxParagraphs: 4);
    final String body = loaded.article.body;
    if (body.length < 60) {
      throw SourceException('条目正文过短：$title');
    }
    final String displayTitle = loaded.article.title.isNotEmpty
        ? loaded.article.title
        : (subtitleLabel?.isNotEmpty == true ? subtitleLabel! : title);
    return TextCard(
      id: 'wiki:$lang:${title.replaceAll(' ', '_')}',
      kind: kind,
      title: displayTitle,
      subtitle: lang == 'zh' ? '维基百科 · 中文' : '维基百科 · 英文',
      body: body,
      attribution: AdapterAttribution.wikipedia,
      sourceUrl:
          'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      links: loaded.links,
      depth: depth,
      fetchedAt: DateTime.now(),
    );
  }

  Future<WikiCandidate?> _nextCandidate({required bool chineseOnly}) async {
    // 英文/中文候选池不能混用，否则语言滑块归零后仍可能消费旧英文候选。
    if (_poolMode != chineseOnly) {
      _pool.clear();
      _poolMode = chineseOnly;
    }
    while (_pool.isNotEmpty) {
      final WikiCandidate candidate = _pool.removeAt(0);
      if (candidate.sitelinks > _settings.wikiRarity.maxSitelinks) continue;
      if (_recent.contains(candidate.title)) continue;
      return candidate;
    }
    final List<WikiCandidate> fetched = await _wiki.randomCandidates(
      classes: academicClasses,
      maxSitelinks: _settings.wikiRarity.maxSitelinks,
      chineseOnly: chineseOnly,
    );
    _pool
      ..clear()
      ..addAll(_wiki.shuffled(fetched));
    if (_pool.isEmpty) return null;
    return _nextCandidate(chineseOnly: chineseOnly);
  }

  bool? _poolMode;

  void _remember(String title) {
    _recent
      ..remove(title)
      ..add(title);
    while (_recent.length > _recentWindow) {
      _recent.removeAt(0);
    }
  }
}
