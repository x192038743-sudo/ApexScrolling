import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import '../text_cleaner.dart';
import 'card_adapter.dart';

/// 诗词名句：优先使用随包的完整诗词选集，网络不可用时也能正常出卡；
/// 选集不可用时再退回今日诗词 API。
class PoetryAdapter implements CardAdapter {
  PoetryAdapter(
    this._net, {
    Random? random,
    AssetBundle? bundle,
    bool useBundledPoems = true,
  }) : _rng = random ?? Random(),
       _bundle = bundle ?? rootBundle,
       _useBundledPoems = useBundledPoems;

  final NetClient _net;
  final Random _rng;
  final AssetBundle _bundle;
  final bool _useBundledPoems;
  List<_BundledPoem>? _poems;
  final Set<String> _recentIds = <String>{};

  static const List<String> _assetPaths = <String>[
    'assets/poems/tangshi.json',
    'assets/poems/songshi.json',
    'assets/poems/songci.json',
    'assets/poems/mingqing.json',
  ];

  @override
  CardKind get kind => CardKind.poetry;

  @override
  String get displayName => '诗词名句';

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    if (_useBundledPoems) {
      final List<_BundledPoem> poems = await _loadBundledPoems();
      final _BundledPoem? poem = _nextBundledPoem(poems);
      if (poem != null) {
        _recentIds.add(poem.id);
        return TextCard(
          id: poem.id,
          kind: kind,
          title: poem.title,
          subtitle: '${poem.author} · ${poem.collection}',
          body: poem.lines.join('\n'),
          attribution: AdapterAttribution.wikisource,
          sourceUrl:
              'https://zh.wikisource.org/wiki/${Uri.encodeComponent(poem.title)}',
          fetchedAt: DateTime.now(),
        );
      }
    }

    final Map<String, dynamic> json = await _net.getJson(
      Uri.parse(Endpoints.jinrishiciApi),
    );
    final String content = (json['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw SourceException('今日诗词返回空内容');
    }
    final String origin = (json['origin'] ?? '').toString().trim();
    final String author = (json['author'] ?? '').toString().trim();

    return TextCard(
      id: 'poetry:${content.hashCode}',
      kind: kind,
      title: origin.isEmpty ? '诗词名句' : origin,
      subtitle: author.isEmpty ? '今日诗词' : '$author · 今日诗词',
      body: content,
      attribution: AdapterAttribution.jinrishici,
      sourceUrl: 'https://www.jinrishici.com/',
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<_BundledPoem>> _loadBundledPoems() async {
    final List<_BundledPoem>? cached = _poems;
    if (cached != null) return cached;

    final List<_BundledPoem> loaded = <_BundledPoem>[];
    for (final String path in _assetPaths) {
      try {
        final String raw = await _bundle.loadString(path);
        final Object? decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final String collection =
            decoded['collection']?.toString().trim() ?? '';
        final Object? poems = decoded['poems'];
        if (poems is! List) continue;
        for (final Object? item in poems) {
          if (item is! Map) continue;
          final String title = _cleanValue(item['title']);
          final String author = _cleanValue(item['author']);
          final Object? rawLines = item['lines'];
          if (title.isEmpty || author.isEmpty || rawLines is! List) continue;
          final List<String> lines = rawLines
              .map((Object? line) => _cleanValue(line))
              .where((String line) => line.isNotEmpty)
              .toList(growable: false);
          final String body = lines.join('\n');
          // 只接纳至少两行的完整诗词，过滤目录、注释和抓取残片。
          if (lines.length < 2 || body.length < 16 || body.length > 2200) {
            continue;
          }
          if (_looksLikeMarkup('$title\n$body')) continue;
          loaded.add(
            _BundledPoem(
              id: 'poetry:bundled:${_stableId(collection, title, body)}',
              collection: collection.isEmpty ? '诗词选集' : collection,
              title: title,
              author: author,
              lines: lines,
            ),
          );
        }
      } on Object {
        // 工具脚本 / 非 Flutter 环境没有 AssetBundle 时，交给 API 兜底。
        continue;
      }
    }
    _poems = loaded;
    return loaded;
  }

  _BundledPoem? _nextBundledPoem(List<_BundledPoem> poems) {
    if (poems.isEmpty) return null;
    List<_BundledPoem> candidates = poems
        .where((_BundledPoem poem) => !_recentIds.contains(poem.id))
        .toList(growable: false);
    if (candidates.isEmpty) {
      _recentIds.clear();
      candidates = poems;
    }
    return candidates[_rng.nextInt(candidates.length)];
  }

  static String _cleanValue(Object? value) {
    if (value == null) return '';
    return TextCleaner.normalizeWhitespace(value.toString())
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\[\[([^\[\]|]+)\]\]'), r'\1')
        .trim();
  }

  static bool _looksLikeMarkup(String text) =>
      text.contains('{{') ||
      text.contains('}}') ||
      text.contains('[[', 0) ||
      text.contains(']]') ||
      text.contains('-{') ||
      text.contains('}-') ||
      RegExp(
        r'^(?:category|分类|分類):',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(text) ||
      RegExp(r'^={2,}', multiLine: true).hasMatch(text);

  static String _stableId(String collection, String title, String body) =>
      '${collection.hashCode}:${title.hashCode}:${body.hashCode}';
}

class _BundledPoem {
  const _BundledPoem({
    required this.id,
    required this.collection,
    required this.title,
    required this.author,
    required this.lines,
  });

  final String id;
  final String collection;
  final String title;
  final String author;
  final List<String> lines;
}
