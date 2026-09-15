import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../presets.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'gutendex_client.dart';
import 'mediawiki_client.dart';

/// 短篇小说 / 散文：整篇成卡。
///
/// 中文走维基文库（鲁迅、朱自清、郁达夫等白话作品），
/// 英文走古登堡计划（按章取一整章）。
class ProseAdapter implements CardAdapter {
  ProseAdapter(NetClient net, {Random? random})
    : _rng = random ?? Random(),
      _wikisource = MediaWikiClient(net, apiUrl: Endpoints.wikisourceApi),
      _gutendex = GutendexClient(net, random: random);

  static const int maxChars = 15000;
  static const int minChineseChars = 300;

  final Random _rng;
  final MediaWikiClient _wikisource;
  final GutendexClient _gutendex;

  final List<String> _recent = <String>[];
  static const int _recentWindow = 10;

  @override
  CardKind get kind => CardKind.prose;

  @override
  String get displayName => '短篇小说 / 散文';

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
    throw SourceException('短篇小说抓取失败：${lastError ?? '无可用篇目'}');
  }

  Future<TextCard?> _fetchChinese() async {
    final List<WikisourceWork> works = List<WikisourceWork>.of(proseWorksZh)
      ..shuffle(_rng);
    for (final WikisourceWork work in works.take(6)) {
      if (_recent.contains(work.title)) continue;
      final String text = await _wikisource.fetchPlainText(work.title);
      if (text.length < minChineseChars) continue;
      if (TextCleaner.looksLikeIndex(text)) continue;
      final String body = TextCleaner.limitToWholeParagraphs(
        text,
        maxChars: maxChars,
      );
      if (body.length < minChineseChars) continue;
      _remember(work.title);
      return TextCard(
        id: 'prose:zh:${work.title}',
        kind: kind,
        title: work.display,
        subtitle: '${work.author} · 维基文库',
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
      authors: proseAuthorsEn,
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
      id: 'prose:en:$bookId',
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
