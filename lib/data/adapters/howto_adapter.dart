import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../presets.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'mediawiki_client.dart';

/// 实用技能教学：wikiHow 步骤卡（中/英文站），
/// 站点不可达时自动退回中文维基教科书的教程条目。
class HowToAdapter implements CardAdapter {
  HowToAdapter(NetClient net, {Random? random})
    : _net = net,
      _rng = random ?? Random(),
      _wikibooks = MediaWikiClient(net, apiUrl: Endpoints.wikibooksApi);

  final NetClient _net;
  final Random _rng;
  final MediaWikiClient _wikibooks;

  /// 会话内最近出过的条目：避免短时间内重复刷到同一篇。
  final List<String> _recentTitles = <String>[];
  static const int _recentWindow = 12;

  @override
  CardKind get kind => CardKind.howTo;

  @override
  String get displayName => '实用技能教程';

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    // 英文占比开启时先试英文站；中文模式只用中文站，避免出英文卡片。
    final List<String> wikiHowApis = preferEnglish
        ? <String>[Endpoints.wikihowEnApi, Endpoints.wikihowZhApi]
        : <String>[Endpoints.wikihowZhApi];
    for (final String api in wikiHowApis) {
      try {
        final TextCard? card = await _fetchWikiHow(api);
        if (card != null) return card;
      } on SourceException {
        continue;
      }
    }
    try {
      final TextCard? card = await _fetchWikibooks();
      if (card != null) return card;
    } on SourceException {
      // 落到统一异常。
    }
    throw SourceException('实用技能源不可用（wikiHow / 维基教科书）');
  }

  /// wikiHow：随机条目 → 取 wikitext → 解析 `#` 编号步骤。
  Future<TextCard?> _fetchWikiHow(String apiUrl) async {
    final Uri randomUri = Uri.parse(apiUrl).replace(
      queryParameters: <String, String>{
        'action': 'query',
        'format': 'json',
        'list': 'random',
        'rnnamespace': '0',
        'rnlimit': '1',
      },
    );
    final Map<String, dynamic> randomJson = await _net.getJson(randomUri);
    final Object? randomList =
        (randomJson['query'] as Map<String, dynamic>?)?['random'];
    if (randomList is! List || randomList.isEmpty) return null;
    final Map<String, dynamic> first = (randomList.first as Map)
        .cast<String, dynamic>();
    final String title = first['title']?.toString() ?? '';
    final String pageId = first['id']?.toString() ?? '';
    if (title.isEmpty || pageId.isEmpty) return null;
    // wikiHow 的 random API 在部分网络节点会重复返回同一页，
    // 这里和维基教科书路径共用最近标题窗口，避免信息流循环。
    if (_recentTitles.contains(title)) return null;

    final Uri contentUri = Uri.parse(apiUrl).replace(
      queryParameters: <String, String>{
        'action': 'query',
        'format': 'json',
        'prop': 'revisions',
        'rvprop': 'content',
        'rvslots': 'main',
        'pageids': pageId,
      },
    );
    final Map<String, dynamic> contentJson = await _net.getJson(contentUri);
    final Object? pages =
        (contentJson['query'] as Map<String, dynamic>?)?['pages'];
    if (pages is! Map) return null;
    final Object? page = pages.values.isEmpty ? null : pages.values.first;
    if (page is! Map) return null;
    final Object? revisions = page['revisions'];
    if (revisions is! List || revisions.isEmpty) return null;
    final Object? slots = (revisions.first as Map)['slots'];
    if (slots is! Map) return null;
    final Object? main = slots['main'];
    final String wikitext = main is Map ? (main['*']?.toString() ?? '') : '';
    if (wikitext.isEmpty) return null;

    final List<String> steps = _parseWikiHowSteps(wikitext);
    final String intro = _parseWikiHowIntro(wikitext);
    if (steps.isEmpty && intro.length < 120) return null;
    final bool chinese = apiUrl.contains('zh.');
    _remember(title);
    return TextCard(
      id: 'howto:wikihow:$pageId',
      kind: kind,
      title: title,
      subtitle: chinese ? 'wikiHow · 中文' : 'wikiHow · English',
      body: intro.isNotEmpty ? intro : '按以下步骤操作：',
      steps: steps,
      attribution: AdapterAttribution.wikihow,
      sourceUrl: Uri.parse(apiUrl)
          .resolve('/${Uri.encodeComponent(title.replaceAll(' ', '-'))}')
          .toString(),
      fetchedAt: DateTime.now(),
    );
  }

  /// 维基教科书：预置检索词 → 随机条目 → 正文 + 列表步骤。
  Future<TextCard?> _fetchWikibooks() async {
    final List<String> queries = List<String>.of(howToQueriesZh)..shuffle(_rng);
    final Set<String> seenTitles = <String>{};
    final List<({String title, String html, String text})> fallbacks =
        <({String title, String html, String text})>[];

    for (final String query in queries.take(6)) {
      final List<String> titles = await _wikibooks.searchTitles(
        query,
        prefix: query.endsWith('/'),
      );
      final List<String> pool = List<String>.of(titles)..shuffle(_rng);
      for (final String title in pool.take(4)) {
        if (!seenTitles.add(title)) continue;
        // 只保留「能跟着做」的主题，过滤教科书式理论章节与赛事特刊。
        if (!_isPracticalTitle(title)) continue;
        if (_recentTitles.contains(title)) continue;
        final String html = await _wikibooks.fetchPageHtml(title);
        if (html.isEmpty) continue;
        // 同一份 HTML 既取正文也取编号步骤，避免重复请求。
        final String text = MediaWikiClient.cleanArticleHtml(html);
        if (text.length < 400) continue;
        if (TextCleaner.looksLikeIndex(text)) continue;
        final List<String> steps = TextCleaner.extractOrderedListItems(html);
        // 「能跟着做」的教程优先：有编号步骤直接成卡。
        if (steps.length >= 2) {
          final TextCard card = _wikibooksCard(title, text, steps);
          if (card.body.length >= 100) {
            _remember(title);
            return card;
          }
        }
        fallbacks.add((title: title, html: html, text: text));
      }
      if (fallbacks.length >= 3) break;
    }
    if (fallbacks.isEmpty) return null;
    final ({String title, String html, String text}) pick = fallbacks.first;
    final TextCard card = _wikibooksCard(
      pick.title,
      pick.text,
      TextCleaner.extractOrderedListItems(pick.html),
    );
    if (card.body.length < 100) return null;
    _remember(pick.title);
    return card;
  }

  void _remember(String title) {
    _recentTitles
      ..remove(title)
      ..add(title);
    while (_recentTitles.length > _recentWindow) {
      _recentTitles.removeAt(0);
    }
  }

  /// 根名是否属于「实用主题」白名单（食谱、急救、手工……）。
  static bool _isPracticalTitle(String title) {
    final String root = title.split('/').first.trim();
    if (root.isEmpty) return false;
    return practicalBookRoots.any(root.contains);
  }

  TextCard _wikibooksCard(String title, String text, List<String> steps) {
    // 有编号步骤时正文取开头简介（更像教程），否则随机取一段正文。
    final String intro = TextCleaner.splitParagraphs(
      text,
    ).take(2).join('\n\n').trim();
    final String excerpt = steps.isNotEmpty && intro.length >= 60
        ? intro
        : TextCleaner.sliceExcerpt(
            text,
            minChars: 200,
            maxChars: 520,
            random: _rng,
          );
    return TextCard(
      id: 'howto:wikibooks:$title',
      kind: kind,
      title: title,
      subtitle: '维基教科书 · 中文',
      body: excerpt,
      steps: steps,
      attribution: AdapterAttribution.wikibooks,
      sourceUrl: 'https://zh.wikibooks.org/wiki/${Uri.encodeComponent(title)}',
      fetchedAt: DateTime.now(),
    );
  }

  /// 从 wikiHow wikitext 中抽取一级编号步骤。
  static List<String> _parseWikiHowSteps(String wikitext) {
    final List<String> steps = <String>[];
    for (final String rawLine in wikitext.split('\n')) {
      final String line = rawLine.trim();
      if (!line.startsWith('#')) continue;
      if (line.startsWith('##')) continue;
      final String cleaned = TextCleaner.stripWikitext(
        line.replaceFirst(RegExp(r'^#+'), ''),
      );
      if (cleaned.length < 4 || cleaned.length > 400) continue;
      steps.add(cleaned);
      if (steps.length >= 12) break;
    }
    return steps;
  }

  /// 导语：第一个小节标题之前的段落。
  static String _parseWikiHowIntro(String wikitext) {
    final List<String> introLines = <String>[];
    for (final String rawLine in wikitext.split('\n')) {
      final String line = rawLine.trim();
      if (line.startsWith('==')) break;
      introLines.add(line);
    }
    final String cleaned = TextCleaner.stripWikitext(introLines.join('\n'));
    final List<String> paragraphs = TextCleaner.splitParagraphs(cleaned);
    return paragraphs.take(2).join('\n\n');
  }
}
