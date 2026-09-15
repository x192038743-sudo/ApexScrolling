import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../presets.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'gutendex_client.dart';
import 'mediawiki_client.dart';

/// 古文经典：整篇成卡。
///
/// 中文走维基文库（整页正文，文言卡署名标注「文言」）；
/// 英文走古登堡计划（按章取一整章）。目录型页面会被过滤掉。
class ClassicExcerptAdapter implements CardAdapter {
  ClassicExcerptAdapter(NetClient net, {Random? random})
    : _rng = random ?? Random(),
      _wikisource = MediaWikiClient(net, apiUrl: Endpoints.wikisourceApi),
      _gutendex = GutendexClient(net, random: random);

  /// 单卡正文上限（整篇作品的截断上限）。
  static const int maxChars = 15000;

  /// 文言经典的正文下限（《陋室銘》这类极短名篇也要能出）。
  static const int minChineseChars = 90;

  final Random _rng;
  final MediaWikiClient _wikisource;
  final GutendexClient _gutendex;

  final List<String> _recent = <String>[];
  static const int _recentWindow = 10;

  @override
  CardKind get kind => CardKind.classicExcerpt;

  @override
  String get displayName => '经典书籍选段';

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    final List<Future<TextCard?> Function()> chain = preferEnglish
        ? [_fetchEnglish, _fetchChinese]
        : [_fetchChinese];
    Object? lastError;
    for (final Future<TextCard?> Function() provider in chain) {
      for (var attempt = 0; attempt < NetPolicy.adapterAttempts; attempt++) {
        try {
          final TextCard? card = await provider();
          if (card != null) return card;
          break;
        } on SourceException catch (error) {
          lastError = error;
        }
      }
    }
    throw SourceException('经典抓取失败：${lastError ?? '无可用书目'}');
  }

  Future<TextCard?> _fetchChinese() async {
    final List<WikisourceWork> works = List<WikisourceWork>.of(classicWorksZh)
      ..shuffle(_rng);
    for (final WikisourceWork work in works.take(6)) {
      if (_recent.contains(work.title)) continue;
      final String text = await _wikisource.fetchPlainText(work.title);
      if (text.length < minChineseChars) continue;
      // 目录 / 篇目索引页直接跳过（《道德經》《古詩十九首》这类）。
      if (TextCleaner.looksLikeIndex(text)) continue;
      final String body = TextCleaner.limitToWholeParagraphs(
        text,
        maxChars: maxChars,
      );
      if (body.length < minChineseChars) continue;
      _remember(work.title);
      return TextCard(
        id: 'classic:zh:${work.title}',
        kind: kind,
        title: work.display,
        subtitle: '${work.author} · 维基文库${work.classical ? ' · 文言' : ''}',
        body: body,
        attribution: AdapterAttribution.wikisource,
        sourceUrl:
            'https://zh.wikisource.org/wiki/${Uri.encodeComponent(work.title)}',
        fetchedAt: DateTime.now(),
      );
    }
    return null;
  }

  Future<TextCard?> _fetchEnglish() async {
    final Map<String, dynamic>? book = await _gutendex.randomBook(
      presetIds: classicWorksEn
          .map((GutenbergWork work) => work.id)
          .toList(growable: false),
    );
    if (book == null) return null;
    final int bookId = (book['id'] as int?) ?? 0;
    if (_recent.contains('en:$bookId')) return null;
    final String? chapter = await _gutendex.pickWholeChapter(
      book,
      maxChars: maxChars,
    );
    if (chapter == null) return null;
    _remember('en:$bookId');
    return TextCard(
      id: 'classic:en:$bookId',
      kind: kind,
      title: GutendexClient.bookTitle(book),
      subtitle: '${GutendexClient.bookAuthor(book)} · 古登堡计划',
      body: chapter,
      attribution: AdapterAttribution.gutenberg,
      sourceUrl: 'https://www.gutenberg.org/ebooks/$bookId',
      fetchedAt: DateTime.now(),
    );
  }

  void _remember(String key) {
    _recent
      ..remove(key)
      ..add(key);
    while (_recent.length > _recentWindow) {
      _recent.removeAt(0);
    }
  }
}
