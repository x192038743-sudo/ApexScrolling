import 'dart:math';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../presets.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';
import 'gutendex_client.dart';
import 'mediawiki_client.dart';

/// 短篇小说 / 散文：中文维基文库（鲁迅、朱自清等）+ 古登堡计划
/// （契诃夫、爱伦·坡等）。随机取一段完整场景，按段落边界切。
class ProseAdapter implements CardAdapter {
  ProseAdapter(NetClient net, {Random? random})
      : _rng = random ?? Random(),
        _wikisource = MediaWikiClient(net, apiUrl: Endpoints.wikisourceApi),
        _gutendex = GutendexClient(net, random: random);

  final Random _rng;
  final MediaWikiClient _wikisource;
  final GutendexClient _gutendex;

  @override
  CardKind get kind => CardKind.prose;

  @override
  String get displayName => '短篇小说 / 散文';

  @override
  Future<TextCard> fetch() async {
    Object? lastError;
    for (var attempt = 0; attempt < NetPolicy.adapterAttempts; attempt++) {
      final bool chinese = _rng.nextBool();
      try {
        final TextCard? card =
            chinese ? await _fetchChinese() : await _fetchEnglish();
        if (card != null) return card;
      } on SourceException catch (error) {
        lastError = error;
      }
    }
    throw SourceException('短篇小说抓取失败：${lastError ?? '无可用篇目'}');
  }

  Future<TextCard?> _fetchChinese() async {
    final List<WikisourceWork> works = List<WikisourceWork>.of(proseWorksZh)
      ..shuffle(_rng);
    for (final WikisourceWork work in works.take(4)) {
      final String text = await _wikisource.fetchPlainText(work.title);
      if (text.length < 500) continue;
      final String excerpt = TextCleaner.sliceExcerpt(
        text,
        minChars: 300,
        maxChars: 600,
        random: _rng,
      );
      if (excerpt.length < 120) continue;
      return TextCard(
        id: 'prose:zh:${work.title}',
        kind: kind,
        title: work.display,
        subtitle: '${work.author} · 维基文库',
        body: excerpt,
        attribution: AdapterAttribution.wikisource,
        sourceUrl:
            'https://zh.wikisource.org/wiki/${Uri.encodeComponent(work.title)}',
        fetchedAt: DateTime.now(),
      );
    }
    return null;
  }

  Future<TextCard?> _fetchEnglish() async {
    final Map<String, dynamic>? book =
        await _gutendex.randomBook(authors: proseAuthorsEn);
    if (book == null) return null;
    final String text = await _gutendex.fetchPlainText(book);
    if (text.length < 800) return null;
    final String excerpt = TextCleaner.sliceExcerpt(
      text,
      minChars: 300,
      maxChars: 600,
      random: _rng,
    );
    if (excerpt.length < 120) return null;
    return TextCard(
      id: 'prose:en:${book['id']}',
      kind: kind,
      title: GutendexClient.bookTitle(book),
      subtitle: '${GutendexClient.bookAuthor(book)} · 古登堡计划',
      body: excerpt,
      attribution: AdapterAttribution.gutenberg,
      sourceUrl: 'https://www.gutenberg.org/ebooks/${book['id']}',
      fetchedAt: DateTime.now(),
    );
  }
}
