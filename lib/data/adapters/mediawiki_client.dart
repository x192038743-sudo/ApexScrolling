import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../net_client.dart';
import '../text_cleaner.dart';

/// 通用 MediaWiki Action API 客户端（维基文库 / 维基教科书）。
///
/// 使用 `action=parse` 而不是 `prop=extracts`：文库中大量作品正文放在
/// 子页面里由头部模板嵌入，TextExtracts 会返回空内容。
class MediaWikiClient {
  MediaWikiClient(this._net, {required String apiUrl}) : _apiUrl = apiUrl;

  final NetClient _net;
  final String _apiUrl;
  final Map<String, String> _memoryCache = <String, String>{};

  /// 返回清洗后的正文纯文本；条目不存在/为空时返回空串。
  Future<String> fetchPlainText(String title) async {
    final String? cached = _memoryCache[title];
    if (cached != null) return cached;
    final String html = await fetchPageHtml(title);
    if (html.isEmpty) return '';
    final String plain = cleanArticleHtml(html);
    if (plain.length > 200) {
      _memoryCache[title] = plain;
    }
    return plain;
  }

  /// 取整页渲染 HTML（已展开模板与嵌入子页）。
  Future<String> fetchPageHtml(String title) async {
    final Uri uri = Uri.parse(_apiUrl).replace(
      queryParameters: <String, String>{
        'action': 'parse',
        'format': 'json',
        'redirects': '1',
        'prop': 'text',
        'disableeditsection': '1',
        'disabletoc': '1',
        'page': title,
      },
    );
    final Map<String, dynamic> json = await _net.getJson(uri);
    final Object? parse = json['parse'];
    if (parse is! Map<String, dynamic>) {
      // 条目不存在时 MediaWiki 返回 error 字段。
      return '';
    }
    final Object? text = (parse['text'] as Map<String, dynamic>?)?['*'];
    if (text is! String || text.isEmpty) return '';
    return text;
  }

  /// 搜索条目名（用于挑选真实存在的作品子页）。
  ///
  /// [prefix] 为 true 时按标题前缀检索（如「食谱/」下的菜谱子页）。
  Future<List<String>> searchTitles(
    String query, {
    int limit = 8,
    bool prefix = false,
  }) async {
    final Uri uri = Uri.parse(_apiUrl).replace(
      queryParameters: <String, String>{
        'action': 'query',
        'format': 'json',
        if (prefix) 'list': 'prefixsearch',
        if (prefix) 'pssearch': query,
        if (prefix) 'pslimit': '$limit',
        if (!prefix) 'list': 'search',
        if (!prefix) 'srsearch': query,
        if (!prefix) 'srlimit': '$limit',
        if (!prefix) 'srnamespace': '0',
      },
    );
    final Map<String, dynamic> json = await _net.getJson(uri);
    final List<dynamic>? items = _pickList(json['query'], prefix);
    if (items == null) return const <String>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> e) => e['title']?.toString() ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
  }

  static List<dynamic>? _pickList(Object? querySection, bool prefix) {
    if (querySection is! Map) return null;
    final Object? value = querySection[prefix ? 'prefixsearch' : 'search'];
    return value is List ? value : null;
  }

  /// 去除文库页面上的导航/版权/姊妹项目等版式残留。
  static String cleanArticleHtml(String html) {
    final Document doc = html_parser.parse(html);
    const List<String> selectors = <String>[
      'style',
      'script',
      'table',
      '.header',
      '.ws-header',
      '#sisterprojects',
      '.sisterproject',
      '.sister-project',
      '.noprint',
      '.navigation-not-searchable',
      '.mw-editsection',
      '.toc',
      '#toc',
      '.catlinks',
      '.licenseContainer',
      '.mw-empty-elt',
      '.printfooter',
    ];
    for (final String selector in selectors) {
      for (final Element el
          in doc.querySelectorAll(selector).toList(growable: false)) {
        el.remove();
      }
    }
    final Element? root =
        doc.querySelector('.mw-parser-output') ?? doc.body ?? doc.documentElement;
    final String raw = root?.text ?? '';
    return _stripChromeLines(TextCleaner.normalizeWhitespace(raw));
  }

  static String _stripChromeLines(String text) {
    final List<String> kept = <String>[];
    for (final String rawLine in text.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        kept.add('');
        continue;
      }
      if (line.contains('姊妹计划') ||
          line.contains('姊妹項目') ||
          line.contains('维基百科') && line.length < 60 ||
          RegExp(r'^[◄►←→\s]+$').hasMatch(line) ||
          RegExp(r'^(本作品|本作品收錄於|This work)').hasMatch(line)) {
        continue;
      }
      kept.add(line);
    }
    return TextCleaner.normalizeWhitespace(kept.join('\n'));
  }
}
