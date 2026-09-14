import 'dart:convert';
import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 文本清洗工具：把各数据源的 HTML / wikitext / 公版纯文本
/// 统一整理成「可直接阅读的纯文字」。
class TextCleaner {
  const TextCleaner._();

  /// 字节解码：优先 UTF-8，失败时退回 latin1（古登堡部分老文件为
  /// us-ascii / ISO-8859-1，直接 utf8 解码会抛异常）。
  static String decodeBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// 折叠空白：全角空格、不断行空格、零宽字符统一处理。
  static String normalizeWhitespace(String input) {
    var text = input
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll('\ufeff', '')
        .replaceAll('\u200b', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    // 删除行内多余空格，保留段落换行。
    text = text
        .split('\n')
        .map((String line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  /// 去掉行内的引用角标，如 `[1]`、`[註 1]`、`[citation needed]`。
  static String stripCitationMarks(String input) {
    return input
        .replaceAll(RegExp(r'\[\s*(?:註|注|编辑|\d+)\s*\]'), '')
        .replaceAll(RegExp(r'\[[a-zA-Z ]{0,20}\]'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '');
  }

  /// HTML → 纯文本（保守：保留段落结构）。
  static String htmlToPlainText(String html) {
    final Document doc = html_parser.parse(html);
    _stripNoiseNodes(doc);
    final Element? body = doc.body;
    if (body == null) return normalizeWhitespace(doc.text ?? '');
    final String withBreaks = body.innerHtml
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final DocumentFragment reparsed = html_parser.parseFragment(withBreaks);
    return normalizeWhitespace(stripCitationMarks(reparsed.text ?? ''));
  }

  /// 提取条目导语段落：只取第一个二级标题之前的正文。
  static ExtractedArticle extractIntro(
    String html, {
    int maxParagraphs = 3,
    int minParagraphLength = 24,
  }) {
    final Document doc = html_parser.parse(html);
    final String title = _firstNonEmpty(
      <String>[
        doc.querySelector('h1')?.text ?? '',
        doc.querySelector('title')?.text ?? '',
      ],
    );
    _stripNoiseNodes(doc);

    final List<String> paragraphs = <String>[];
    for (final Element el in doc.querySelectorAll('h1, h2, h3, p')) {
      final String tag = el.localName ?? '';
      if (tag != 'p') {
        // 遇到第一个小节标题即认为导语结束。
        if (paragraphs.isNotEmpty) break;
        continue;
      }
      final String text = normalizeWhitespace(
        stripCitationMarks(el.text),
      );
      if (text.length < minParagraphLength) continue;
      paragraphs.add(text);
      if (paragraphs.length >= maxParagraphs) break;
    }
    return ExtractedArticle(title: title, paragraphs: paragraphs);
  }

  /// 解析 wikiHow / 维基文库等条目的内部链接，用于「兔子洞」。
  static List<({String label, String title, String lang})> extractWikiLinks(
    String html, {
    String lang = 'zh',
    int limit = 4,
  }) {
    final Document doc = html_parser.parse(html);
    final List<({String label, String title, String lang})> result =
        <({String label, String title, String lang})>[];
    final Set<String> seen = <String>{};
    const List<String> blockedPrefixes = <String>[
      'File:',
      'Image:',
      'Category:',
      'Help:',
      'Wikipedia:',
      'Template:',
      'Portal:',
      'Special:',
      'Talk:',
      'User:',
      'Draft:',
      'Module:',
      'MediaWiki:',
      '文件:',
      '分类:',
      '帮助:',
      '维基百科:',
      '模板:',
      '主题:',
      '特殊:',
      '讨论:',
      '用户:',
      'Wikipedia',
      'Main Page',
      '首页',
    ];
    for (final Element a in doc.querySelectorAll('a')) {
      final String? href = a.attributes['href'];
      if (href == null) continue;
      String? raw;
      if (href.startsWith('./')) {
        raw = href.substring(2);
      } else if (href.startsWith('/wiki/')) {
        raw = href.substring(6);
      } else {
        continue;
      }
      if (raw.contains('#')) raw = raw.split('#').first;
      if (raw.isEmpty) continue;
      raw = _safeDecode(raw).replaceAll('_', ' ').trim();
      if (raw.length < 2 || raw.length > 40) continue;
      if (raw.contains(RegExp(r'^[\d\s.,;:()\[\]-]+$'))) continue;
      if (blockedPrefixes.any(raw.startsWith)) continue;
      final String label = normalizeWhitespace(a.text);
      if (label.isEmpty) continue;
      // 过滤引用角标、纯数字、纯标点这类「伪链接」。
      if (label.length < 2 || label.length > 40) continue;
      if (RegExp(r'^[\[\(【（]?\s*\d+\s*[\]\)】）]?$').hasMatch(label)) continue;
      if (RegExp(r'^[\s\d\p{P}\p{S}]+$', unicode: true).hasMatch(label)) continue;
      if (!seen.add(raw)) continue;
      result.add((label: label, title: raw, lang: lang));
      if (result.length >= limit) break;
    }
    return result;
  }

  /// wikitext → 纯文本（平衡括号去掉模板、链接、表格、注释）。
  static String stripWikitext(String wikitext) {
    var text = _keepLongTemplateArgs(wikitext);
    text = _removeBalanced(text, '{{', '}}');
    text = text.replaceAll(RegExp(r'<ref[^>]*>.*?</ref>', dotAll: true), '');
    text = text.replaceAll(RegExp(r'<ref[^>]*/>'), '');
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    text = _removeBalanced(text, '{|', '|}');
    text = text.replaceAllMapped(RegExp(r'\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]'),
        (Match m) => m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'\[(?:https?://\S+)\s*([^\]]*)\]'),
        (Match m) => m.group(1) ?? '');
    text = text.replaceAll(RegExp(r"'{2,}"), '');
    text = text.replaceAll(RegExp(r'^[=]{2,}\s*(.*?)\s*[=]{2,}$',
        multiLine: true), r'\1');
    text = htmlToPlainText(text);
    return normalizeWhitespace(text);
  }

  /// 保留 `{{intro|一段说明文字}}` 这类「参数即正文」的模板内容：
  /// wikiHow 的导语、提示常包在模板里，直接整体删除会丢正文。
  static String _keepLongTemplateArgs(String input) {
    return input.replaceAllMapped(
      RegExp(r'\{\{\s*[\w\u4e00-\u9fa5]+\s*\|\s*([^{}|]{16,})\s*\}\}'),
      (Match match) => '\n\n${match.group(1)!.trim()}\n\n',
    );
  }

  /// 古登堡公版文本：去掉头部说明与尾部 license 段落。
  static String stripGutenbergBoilerplate(String raw) {
    var text = raw;
    final RegExp startRe = RegExp(
      r'\*\*\*\s*START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK[^\n]*\*\*\*',
      caseSensitive: false,
    );
    final RegExp endRe = RegExp(
      r'\*\*\*\s*END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK[^\n]*\*\*\*',
      caseSensitive: false,
    );
    final Match? start = startRe.firstMatch(text);
    if (start != null) {
      text = text.substring(start.end);
    }
    final Match? end = endRe.firstMatch(text);
    if (end != null) {
      text = text.substring(0, end.start);
    }
    return normalizeWhitespace(text);
  }

  /// 提取有序列表（`<ol><li>`）里的步骤文本，供技能卡使用。
  static List<String> extractOrderedListItems(String html, {int limit = 12}) {
    final Document doc = html_parser.parse(html);
    _stripNoiseNodes(doc);
    final List<String> steps = <String>[];
    for (final Element list in doc.querySelectorAll('ol')) {
      for (final Element item in list.children) {
        if (item.localName != 'li') continue;
        final String text = normalizeWhitespace(stripCitationMarks(item.text));
        if (text.length < 4 || text.length > 400) continue;
        steps.add(text);
        if (steps.length >= limit) return steps;
      }
      if (steps.isNotEmpty) break;
    }
    return steps;
  }

  /// 按空行切段，过滤只有页码、标号之类的碎片。
  static List<String> splitParagraphs(String text) {
    return normalizeWhitespace(text)
        .split(RegExp(r'\n\s*\n'))
        .map((String p) => p.trim())
        .where((String p) {
      if (p.length < 2) return false;
      final String noPunct = p.replaceAll(
          RegExp(r'[\s\d\p{P}\p{S}]', unicode: true), '');
      return noPunct.isNotEmpty;
    }).toList();
  }

  /// 随机截取 300–600 字的完整段落片段（不腰斩句子）。
  static String sliceExcerpt(
    String text, {
    int minChars = 300,
    int maxChars = 600,
    Random? random,
  }) {
    final Random rng = random ?? Random();
    final List<String> paragraphs = splitParagraphs(text);
    if (paragraphs.isEmpty) return '';

    // 可供起点的段落：自身长度足够，或后续段落能补足。
    final List<int> starts = <int>[];
    for (var i = 0; i < paragraphs.length; i++) {
      var length = 0;
      for (var j = i; j < paragraphs.length && length < minChars; j++) {
        length += paragraphs[j].length;
      }
      if (length >= minChars) starts.add(i);
    }
    if (starts.isEmpty) {
      // 整篇都凑不够 minChars：返回全文（超长时按句切）。
      final String whole = paragraphs.join('\n\n');
      return whole.length <= maxChars
          ? whole
          : _sliceInsideParagraph(whole,
              minChars: minChars, maxChars: maxChars, rng: rng);
    }

    final int start = starts[rng.nextInt(starts.length)];
    final StringBuffer buffer = StringBuffer();
    var lastIndex = start - 1;
    for (var i = start; i < paragraphs.length; i++) {
      final String paragraph = paragraphs[i];
      if (buffer.isNotEmpty) {
        if (buffer.length + 2 + paragraph.length > maxChars) {
          break;
        }
        buffer
          ..write('\n\n')
          ..write(paragraph);
      } else {
        // 首段本身超长：在段落内部按句号取一段。
        if (paragraph.length > maxChars) {
          return _sliceInsideParagraph(
            paragraph,
            minChars: minChars,
            maxChars: maxChars,
            rng: rng,
          );
        }
        buffer.write(paragraph);
      }
      lastIndex = i;
      // 已经落在 300–600 区间时随机收尾，避免每张卡片都一样长。
      if (buffer.length >= minChars && rng.nextBool()) break;
      if (buffer.length >= maxChars) break;
    }

    String result = buffer.toString().trim();
    if (result.length < minChars && lastIndex + 1 < paragraphs.length) {
      // 段落被 maxChars 截断导致偏短：补上下一段，再按句切到上限内。
      result = '$result\n\n${paragraphs[lastIndex + 1]}';
      if (result.length > maxChars) {
        result = _sliceInsideParagraph(result,
            minChars: minChars, maxChars: maxChars, rng: rng);
      }
    }
    return result;
  }

  /// 在超长段落内部按句号边界切片。
  static String _sliceInsideParagraph(
    String paragraph, {
    required int minChars,
    required int maxChars,
    required Random rng,
  }) {
    if (paragraph.length <= maxChars) return paragraph;
    final List<String> sentences = _splitSentences(paragraph);
    if (sentences.length <= 1) {
      return _hardCut(paragraph, minChars: minChars, maxChars: maxChars, rng: rng);
    }

    // 只从「后面还有足够句子」的位置起切，保证凑得满 minChars。
    final List<int> starts = <int>[];
    for (var i = 0; i < sentences.length; i++) {
      var length = 0;
      for (var j = i; j < sentences.length && length < minChars; j++) {
        length += sentences[j].length;
      }
      if (length >= minChars) starts.add(i);
    }
    if (starts.isEmpty) {
      return _hardCut(paragraph, minChars: minChars, maxChars: maxChars, rng: rng);
    }

    final int start = starts[rng.nextInt(starts.length)];
    final StringBuffer buffer = StringBuffer();
    for (var i = start; i < sentences.length; i++) {
      final String sentence = sentences[i];
      if (buffer.isNotEmpty && buffer.length + sentence.length > maxChars) {
        break;
      }
      buffer.write(sentence);
      // 够长即可停，保持随机性。
      if (buffer.length >= minChars && rng.nextBool()) break;
      if (buffer.length >= maxChars) break;
    }
    final String result = buffer.toString().trim();
    return result.length < minChars
        ? _hardCut(paragraph,
            minChars: minChars, maxChars: maxChars, rng: rng)
        : result;
  }

  /// 无法按句子切分时的兜底：按字数硬截断。
  static String _hardCut(
    String paragraph, {
    required int minChars,
    required int maxChars,
    required Random rng,
  }) {
    final int span = maxChars > minChars ? maxChars - minChars : 0;
    final int cut = minChars + (span > 0 ? rng.nextInt(span + 1) : 0);
    return paragraph.substring(0, min(cut, paragraph.length)).trim();
  }

  /// 中英混排的句子切分（标点在句尾，保留标点）。
  static List<String> _splitSentences(String text) {
    const String sep = '\u0001';
    final String marked = text
        .replaceAllMapped(
          RegExp(r'([。！？；!?])\s*'),
          (Match m) => '${m.group(1)}$sep',
        )
        .replaceAllMapped(
          RegExp(r'([.])\s+'),
          (Match m) => '${m.group(1)}$sep',
        );
    return marked
        .split(sep)
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  // -------------------------------------------------------------- 内容质量

  /// 判定一段文本是否只是「目录 / 索引 / 版本列表」而不是正文。
  ///
  /// 维基文库的《道德经》《论语》等页面、食谱里的菜系索引都属于这一类，
  /// 直接成卡会显得毫无意义。只在古文经典 / 小说散文 / 技能教程 / 词条导语上
  /// 使用；诗词（整首分行）不参与判定，避免误杀。
  static bool looksLikeIndex(String text) {
    final String normalized = normalizeWhitespace(text);
    if (normalized.length < 40) return false;

    final List<String> lines = normalized
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 4) return false;

    final RegExp sentenceEnd = RegExp(r'[。！？；!?;]');
    final int shortLines = lines
        .where((String line) =>
            line.length <= 25 && !sentenceEnd.hasMatch(line))
        .length;
    final double shortRatio = shortLines / lines.length;

    final int sentenceCount = RegExp(r'[。！？]').allMatches(normalized).length;
    final int bookTitleMarks = '《'.allMatches(normalized).length;
    final double avgLineLength =
        normalized.replaceAll('\n', '').length / lines.length;

    // ① 绝大多数是"没有句末标点的短行" —— 典型目录。
    if (lines.length >= 5 && shortRatio > 0.6) return true;
    // ② 书名号成串出现且几乎没有完整句子 —— 书目 / 篇目列表。
    if (bookTitleMarks >= 3 && sentenceCount < lines.length * 0.25) return true;
    // ③ 行数多、行很短、几乎没有句子 —— 索引型排版。
    if (lines.length >= 6 && avgLineLength < 30 && sentenceCount <= 2) {
      return true;
    }
    return false;
  }

  /// 把整篇正文限制在 [maxChars] 以内，并保证结尾是完整段落。
  ///
  /// 「整篇」作品可能有好几万字（鲁迅《祝福》约 1.1 万字），不能无上限丢给
  /// 渲染层。这里按自然段累积，截到上限前最后一个完整段落；单段过长时按句号切。
  static String limitToWholeParagraphs(
    String text, {
    int maxChars = 15000,
  }) {
    final String normalized = normalizeWhitespace(text);
    if (normalized.length <= maxChars) return normalized;

    final List<String> paragraphs = splitParagraphs(normalized);
    if (paragraphs.isEmpty) return _cutAtSentence(normalized, maxChars);

    final StringBuffer buffer = StringBuffer();
    for (final String paragraph in paragraphs) {
      if (buffer.isEmpty) {
        if (paragraph.length > maxChars) {
          return _cutAtSentence(paragraph, maxChars);
        }
        buffer.write(paragraph);
        continue;
      }
      if (buffer.length + 2 + paragraph.length > maxChars) break;
      buffer
        ..write('\n\n')
        ..write(paragraph);
    }
    final String result = buffer.toString().trim();
    return result.isEmpty ? _cutAtSentence(normalized, maxChars) : result;
  }

  /// 在 [maxChars] 内按最后一个句末标点收尾（找不到就硬截）。
  static String _cutAtSentence(String text, int maxChars) {
    final String head = text.substring(0, min(maxChars, text.length));
    final int cut = _lastSentenceEnd(head);
    return cut <= 0 ? head.trim() : head.substring(0, cut).trim();
  }

  static int _lastSentenceEnd(String text) {
    final RegExp end = RegExp(r'[。！？；.!?;]');
    var last = -1;
    for (final RegExpMatch match in end.allMatches(text)) {
      last = match.end;
    }
    return last;
  }

  /// 把整本书切成章节（英文 CHAPTER/PART/BOOK、中文 第 N 章/回/卷/節）。
  ///
  /// 古登堡的长篇不再随机切段，而是随机取**一整章**，保证内容完整。
  static List<String> splitChapters(String text) {
    final String normalized = normalizeWhitespace(text);
    if (normalized.isEmpty) return const <String>[];

    final RegExp heading = RegExp(
      r'^\s*(chapter|part|book|section|canto)\b.*$'
      r'|^\s*第\s*[0-9一二三四五六七八九十百零〇]+\s*[章回節节卷篇]\b.*$',
      caseSensitive: false,
    );

    final List<String> chapters = <String>[];
    final StringBuffer buffer = StringBuffer();
    var seenHeading = false;
    for (final String line in normalized.split('\n')) {
      final bool isHeading = heading.hasMatch(line);
      if (isHeading && seenHeading && buffer.toString().trim().length > 400) {
        chapters.add(buffer.toString().trim());
        buffer.clear();
      }
      if (isHeading) seenHeading = true;
      buffer.writeln(line);
    }
    final String tail = buffer.toString().trim();
    if (tail.isNotEmpty) chapters.add(tail);

    // 没有章节标记（单篇/短篇集）时整篇返回。
    if (chapters.length <= 1) return <String>[normalized];
    final List<String> usable =
        chapters.where((String c) => c.length >= 400).toList(growable: false);
    return usable.isEmpty ? <String>[normalized] : usable;
  }

  /// 容错的百分号解码：链接里出现非法转义时退回原串。
  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  static void _stripNoiseNodes(Document doc) {
    const List<String> selectors = <String>[
      'script',
      'style',
      'sup.reference',
      'sup.noprint',
      '.mw-editsection',
      '.reference',
      '.navbox',
      '.metadata',
      '.infobox',
      '.thumb',
      '.mw-empty-elt',
      'table',
      'figure',
      'audio',
      'video',
      'noscript',
    ];
    for (final String selector in selectors) {
      for (final Element el
          in doc.querySelectorAll(selector).toList(growable: false)) {
        el.remove();
      }
    }
  }

  /// 去掉成对出现的模板/表格块（支持嵌套）。
  static String _removeBalanced(String input, String open, String close) {
    final StringBuffer out = StringBuffer();
    var depth = 0;
    var i = 0;
    while (i < input.length) {
      if (input.startsWith(open, i)) {
        depth++;
        i += open.length;
        continue;
      }
      if (input.startsWith(close, i)) {
        if (depth > 0) depth--;
        i += close.length;
        continue;
      }
      if (depth == 0) out.write(input[i]);
      i++;
    }
    return out.toString();
  }

  static String _firstNonEmpty(List<String> candidates) {
    for (final String candidate in candidates) {
      final String cleaned = normalizeWhitespace(candidate);
      if (cleaned.isNotEmpty) {
        // 去掉 Wikipedia 页面标题的后缀。
        return cleaned.replaceAll(RegExp(r'\s*[-–—]\s*维基百科.*$'), '').trim();
      }
    }
    return '';
  }
}

/// 条目导语抽取结果。
class ExtractedArticle {
  const ExtractedArticle({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  String get body => paragraphs.join('\n\n');

  bool get isEmpty => paragraphs.isEmpty;
}
