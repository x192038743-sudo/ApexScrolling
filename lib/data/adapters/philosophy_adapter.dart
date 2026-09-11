import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';

/// 哲学观点：斯坦福哲学百科（SEP）条目导语。
///
/// SEP 无公开 API，这里先取目录页得到条目清单（会话内缓存），
/// 再随机抽取条目并解析导语前 2–3 段。
class PhilosophyAdapter implements CardAdapter {
  PhilosophyAdapter(this._net, {Random? random}) : _rng = random ?? Random();

  final NetClient _net;
  final Random _rng;
  List<({String label, String url})>? _entries;

  @override
  CardKind get kind => CardKind.philosophy;

  @override
  String get displayName => '哲学观点（SEP）';

  @override
  Future<TextCard> fetch() async {
    final List<({String label, String url})> entries = await _loadEntries();
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

  /// 目录页只抓一次，之后复用。
  Future<List<({String label, String url})>> _loadEntries() async {
    final List<({String label, String url})>? cached = _entries;
    if (cached != null && cached.isNotEmpty) return cached;

    final String html =
        await _net.getText(Uri.parse(Endpoints.sepContents));
    final Document doc = html_parser.parse(html);
    final List<({String label, String url})> entries =
        <({String label, String url})>[];
    final Set<String> seen = <String>{};
    for (final Element link in doc.querySelectorAll('a[href]')) {
      final String? href = link.attributes['href'];
      if (href == null || !href.contains('entries/')) continue;
      if (!href.endsWith('/') && !href.contains('entries/')) continue;
      final String label = TextCleaner.normalizeWhitespace(link.text);
      if (label.isEmpty || label.length > 60) continue;
      final String url = href.startsWith('http')
          ? href
          : '${Endpoints.sepBase}/${href.replaceFirst(RegExp(r'^/'), '')}';
      if (!seen.add(url)) continue;
      entries.add((label: label, url: url));
    }
    _entries = entries;
    return entries;
  }
}
