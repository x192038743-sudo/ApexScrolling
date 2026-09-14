import 'dart:math';

import '../../core/endpoints.dart';
import '../net_client.dart';
import '../text_cleaner.dart';

/// 古登堡计划（Gutendex）客户端：随机公版书 + 全文下载（内存缓存）。
class GutendexClient {
  GutendexClient(this._net, {Random? random}) : _rng = random ?? Random();

  final NetClient _net;
  final Random _rng;
  final Map<int, String> _textCache = <int, String>{};

  /// 按编号取书；编号失效时返回 null。
  Future<Map<String, dynamic>?> book(int id) async {
    try {
      return await _net.getJson(Uri.parse('${Endpoints.gutendexApi}/$id'));
    } on SourceException {
      return null;
    }
  }

  /// 按书名 / 作者检索，返回含纯文本格式的书目。
  Future<List<Map<String, dynamic>>> search(
    String query, {
    String languages = 'en',
  }) async {
    final Uri uri = Uri.parse(Endpoints.gutendexApi).replace(
      queryParameters: <String, String>{
        'search': query,
        'languages': languages,
      },
    );
    final Map<String, dynamic> json = await _net.getJson(uri);
    final Object? results = json['results'];
    if (results is! List) return const <Map<String, dynamic>>[];
    return results
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> book) => plainTextUrl(book) != null)
        .toList();
  }

  /// 随机取一本可读的书（先试预置编号，再按作者检索）。
  Future<Map<String, dynamic>?> randomBook({
    List<int>? presetIds,
    List<String>? authors,
  }) async {
    if (presetIds != null && presetIds.isNotEmpty) {
      final List<int> shuffled = List<int>.of(presetIds)..shuffle(_rng);
      for (final int id in shuffled.take(3)) {
        final Map<String, dynamic>? data = await book(id);
        if (data != null && plainTextUrl(data) != null) return data;
      }
    }
    if (authors != null && authors.isNotEmpty) {
      final String author = authors[_rng.nextInt(authors.length)];
      final List<Map<String, dynamic>> found = await search(author);
      if (found.isNotEmpty) {
        return found[_rng.nextInt(min(found.length, 16))];
      }
    }
    return null;
  }

  /// 下载并清洗书籍全文（内存缓存，避免重复下载）。
  Future<String> fetchPlainText(Map<String, dynamic> bookJson) async {
    final Object? rawId = bookJson['id'];
    final int id = rawId is int ? rawId : int.tryParse('$rawId') ?? -1;
    final String? cached = _textCache[id];
    if (cached != null) return cached;

    final String? url = plainTextUrl(bookJson);
    if (url == null) {
      throw SourceException('该书没有纯文本格式');
    }
    final List<int> bytes = await _net.getBytes(Uri.parse(url));
    final String decoded = TextCleaner.decodeBytes(bytes);
    final String text = TextCleaner.stripGutenbergBoilerplate(decoded);
    if (text.length < 400) {
      throw SourceException('书籍正文过短（$id）');
    }
    if (_textCache.length > 8) {
      _textCache.remove(_textCache.keys.first);
    }
    _textCache[id] = text;
    return text;
  }

  /// 选择 UTF-8 优先的纯文本下载地址。
  static String? plainTextUrl(Map<String, dynamic> bookJson) {
    final Object? formats = bookJson['formats'];
    if (formats is! Map) return null;
    const List<String> preferred = <String>[
      'text/plain; charset=utf-8',
      'text/plain; charset=us-ascii',
      'text/plain',
    ];
    for (final String key in preferred) {
      final Object? value = formats[key];
      if (value is String && value.isNotEmpty) return value;
    }
    for (final MapEntry<Object?, Object?> entry in formats.entries) {
      final String key = '${entry.key}';
      final Object? value = entry.value;
      if (key.startsWith('text/plain') && value is String) return value;
    }
    return null;
  }

  static String bookTitle(Map<String, dynamic> bookJson) =>
      (bookJson['title'] as String? ?? '未命名').trim();

  static String bookAuthor(Map<String, dynamic> bookJson) {
    final Object? authors = bookJson['authors'];
    if (authors is List && authors.isNotEmpty) {
      final Object? first = authors.first;
      if (first is Map && first['name'] is String) {
        return (first['name'] as String).trim();
      }
    }
    return '佚名';
  }

  /// 取「一个完整篇章」：优先随机选一整章；没有章节标记就整篇（按上限截断）。
  ///
  /// 目录型章节会被跳过，避免出现"整张卡都是目录"的无意义内容。
  Future<String?> pickWholeChapter(
    Map<String, dynamic> bookJson, {
    int maxChars = 15000,
    int minChars = 400,
  }) async {
    final String text = await fetchPlainText(bookJson);
    if (text.length < minChars) return null;

    final List<String> chapters = TextCleaner.splitChapters(text);
    final List<String> pool = List<String>.of(chapters)..shuffle(_rng);
    for (final String chapter in pool.take(4)) {
      if (TextCleaner.looksLikeIndex(chapter)) continue;
      final String body =
          TextCleaner.limitToWholeParagraphs(chapter, maxChars: maxChars);
      if (body.length < minChars) continue;
      return body;
    }
    return null;
  }
}
