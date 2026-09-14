import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/endpoints.dart';
import '../../models/app_settings.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'wiki_source_client.dart';

/// 哲学观点，双提供者：
/// - 中文：维基百科哲学类冷门词条（哲学概念 / 哲学立场 / 悖论 / 思想实验）；
/// - 英文：斯坦福哲学百科（SEP）条目导语。
///
/// 具体走哪个由英文占比决定（`preferEnglish`），首选失败会自动退回另一个。
class PhilosophyAdapter implements CardAdapter {
  PhilosophyAdapter(
    this._net, {
    Random? random,
    WikiSourceClient? wikiSource,
  })  : _rng = random ?? Random(),
        _wiki = wikiSource ?? WikiSourceClient(_net, random: random);

  final NetClient _net;
  final Random _rng;
  final WikiSourceClient _wiki;

  /// 哲学类目（与冷门词条源不重叠）。
  static const List<String> philosophyClasses = <String>[
    'Q33104279', // 哲学概念
    'Q5389993', // 哲学立场
    'Q483372', // 悖论
    'Q147027', // 思想实验
  ];

  List<({String label, String url})>? _sepEntries;
  final List<WikiCandidate> _pool = <WikiCandidate>[];
  final List<String> _recent = <String>[];
  static const int _recentWindow = 16;

  @override
  CardKind get kind => CardKind.philosophy;

  @override
  String get displayName => '哲学观点';

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    final List<Future<TextCard> Function()> chain =
        preferEnglish ? [_fetchSep, _fetchChinese] : [_fetchChinese, _fetchSep];
    Object? lastError;
    for (final Future<TextCard> Function() provider in chain) {
      try {
        return await provider();
      } on SourceException catch (error) {
        lastError = error;
      }
    }
    throw SourceException('哲学源不可用：$lastError');
  }

  // ------------------------------------------------------------ 中文提供者

  Future<TextCard> _fetchChinese() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final WikiCandidate? candidate = await _nextCandidate();
      if (candidate == null) break;
      try {
        final ({ExtractedArticle article, List<CardLink> links}) loaded =
            await _wiki.loadArticle(candidate.title, lang: 'zh', maxParagraphs: 4);
        if (loaded.article.body.length < 100) continue;
        final String title = loaded.article.title.isNotEmpty
            ? loaded.article.title
            : candidate.label;
        _remember(candidate.title);
        return TextCard(
          id: 'philosophy:zh:${candidate.qid}',
          kind: kind,
          title: title,
          subtitle: '维基百科 · 哲学词条',
          body: loaded.article.body,
          attribution: AdapterAttribution.wikipedia,
          sourceUrl:
              'https://zh.wikipedia.org/wiki/${Uri.encodeComponent(candidate.title.replaceAll(' ', '_'))}',
          links: loaded.links,
          fetchedAt: DateTime.now(),
        );
      } on SourceException catch (error) {
        lastError = error;
      }
    }
    throw SourceException('中文哲学词条不可用：${lastError ?? '无候选'}');
  }

  Future<WikiCandidate?> _nextCandidate() async {
    while (_pool.isNotEmpty) {
      final WikiCandidate candidate = _pool.removeAt(0);
      if (_recent.contains(candidate.title)) continue;
      return candidate;
    }
    final List<WikiCandidate> fetched = await _wiki.randomCandidates(
      classes: philosophyClasses,
      maxSitelinks: 100,
      chineseOnly: true,
    );
    _pool
      ..clear()
      ..addAll(_wiki.shuffled(fetched));
    if (_pool.isEmpty) return null;
    return _nextCandidate();
  }

  void _remember(String title) {
    _recent
      ..remove(title)
      ..add(title);
    while (_recent.length > _recentWindow) {
      _recent.removeAt(0);
    }
  }

  // ------------------------------------------------------------ 英文提供者

  Future<TextCard> _fetchSep() async {
    final List<({String label, String url})> entries = await _loadSepEntries();
    if (entries.isEmpty) {
      throw SourceException('SEP 目录为空');
    }
    final List<({String label, String url})> pool =
        List<({String label, String url})>.of(entries)..shuffle(_rng);
    for (final ({String label, String url}) entry
        in pool.take(NetPolicy.adapterAttempts)) {
      try {
        final String html = await _net.getText(Uri.parse(entry.url));
        final ExtractedArticle article =
            TextCleaner.extractIntro(html, maxParagraphs: 3);
        final String body = article.body;
        if (body.length < 160) continue;
        final String title =
            article.title.isNotEmpty ? article.title : entry.label;
        return TextCard(
          id: 'sep:${entry.url}',
          kind: kind,
          title: title,
          subtitle: 'Stanford Encyclopedia of Philosophy',
          body: body,
          attribution: AdapterAttribution.sep,
          sourceUrl: entry.url,
          fetchedAt: DateTime.now(),
        );
      } on SourceException {
        continue;
      }
    }
    throw SourceException('SEP 条目解析失败');
  }

  /// SEP 目录页只抓一次，之后复用。
  Future<List<({String label, String url})>> _loadSepEntries() async {
    final List<({String label, String url})>? cached = _sepEntries;
    if (cached != null && cached.isNotEmpty) return cached;

    final String html = await _net.getText(Uri.parse(Endpoints.sepContents));
    final Document doc = html_parser.parse(html);
    final List<({String label, String url})> entries =
        <({String label, String url})>[];
    final Set<String> seen = <String>{};
    for (final Element link in doc.querySelectorAll('a[href]')) {
      final String? href = link.attributes['href'];
      if (href == null || !href.contains('entries/')) continue;
      final String label = TextCleaner.normalizeWhitespace(link.text);
      if (label.isEmpty || label.length > 60) continue;
      final String url = href.startsWith('http')
          ? href
          : '${Endpoints.sepBase}/${href.replaceFirst(RegExp(r'^/'), '')}';
      if (!seen.add(url)) continue;
      entries.add((label: label, url: url));
    }
    _sepEntries = entries;
    return entries;
  }
}
