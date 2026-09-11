import 'dart:convert';
import 'dart:math';

import 'package:apex_scrolling/data/text_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextCleaner.decodeBytes', () {
    test('去掉 UTF-8 BOM', () {
      final List<int> bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('老子')];
      expect(TextCleaner.decodeBytes(bytes), '老子');
    });

    test('非法 UTF-8 字节退回 latin1，不抛异常', () {
      final List<int> bytes = <int>[0xC3, 0x28, 0xA9, 0xFF];
      expect(() => TextCleaner.decodeBytes(bytes), returnsNormally);
    });
  });

  group('TextCleaner.extractIntro', () {
    test('只取第一个小节标题之前的段落，并清理引用角标', () {
      final ExtractedArticle article = TextCleaner.extractIntro(
        '<html><body><h1>二项式定理</h1>'
        '<p>第一段介绍该定理的基本含义与历史背景，内容足够长以便通过过滤。<sup class="reference">[1]</sup></p>'
        '<p>第二段讨论组合意义与杨辉三角之间的关系，同样足够长。</p>'
        '<h2>历史</h2>'
        '<p>这一段在标题之后，必须被忽略，而且长度也足够长。</p>'
        '</body></html>',
      );
      expect(article.title, '二项式定理');
      expect(article.paragraphs, hasLength(2));
      expect(article.body, isNot(contains('必须被忽略')));
      expect(article.body, isNot(contains('[1]')));
    });

    test('缺少摘要时返回空正文而不是抛异常', () {
      final ExtractedArticle article =
          TextCleaner.extractIntro('<html><body><h1>空条目</h1></body></html>');
      expect(article.isEmpty, isTrue);
      expect(
        TextCleaner.extractIntro('<html><body></body></html>').isEmpty,
        isTrue,
      );
    });
  });

  group('TextCleaner.extractWikiLinks', () {
    test('过滤文件/分类/锚点等非词条链接', () {
      final List<({String label, String title, String lang})> links =
          TextCleaner.extractWikiLinks(
        '<div><p>'
        '<a href="./组合数">组合数</a>'
        '<a href="./File:Example.png">图</a>'
        '<a href="./Category:数学">分类</a>'
        '<a href="./二项式定理#历史">锚点</a>'
        '<a href="https://example.com/x">外链</a>'
        '<a href="./杨辉三角">杨辉三角</a>'
        '</p></div>',
        limit: 5,
      );
      expect(
        links.map((({String label, String title, String lang}) l) => l.title),
        <String>['组合数', '二项式定理', '杨辉三角'],
      );
    });
  });

  group('TextCleaner.stripWikitext', () {
    test('去掉模板、注释、引用、表格与链接标记', () {
      const String wikitext = '{{header|title=测试}}\n'
          '正文第一句<ref name="a">注</ref>，包含[[内部链接|显示文字]]。\n'
          '<!-- 注释 -->\n'
          '{| class="wikitable"\n|-\n| 表格\n|}\n'
          "'''粗体'''结束。";
      final String cleaned = TextCleaner.stripWikitext(wikitext);
      expect(cleaned, contains('正文第一句，包含显示文字。'));
      expect(cleaned, contains('粗体结束。'));
      expect(cleaned, isNot(contains('header')));
      expect(cleaned, isNot(contains('表格')));
      expect(cleaned, isNot(contains('注释')));
    });
  });

  group('TextCleaner.stripGutenbergBoilerplate', () {
    test('切掉项目说明头尾', () {
      const String raw = '说明\n\n'
          '*** START OF THE PROJECT GUTENBERG EBOOK MEDITATIONS ***\n\n'
          '正文内容。\n\n'
          '*** END OF THE PROJECT GUTENBERG EBOOK MEDITATIONS ***\n\n'
          '许可说明。';
      final String cleaned = TextCleaner.stripGutenbergBoilerplate(raw);
      expect(cleaned, '正文内容。');
    });
  });

  group('TextCleaner.sliceExcerpt', () {
    test('多个段落时输出 300–600 字且落在段落边界', () {
      final String text = List<String>.generate(
        12,
        (int i) => '第$i段：${'内容' * 60}',
      ).join('\n\n');
      for (var seed = 0; seed < 30; seed++) {
        final String excerpt = TextCleaner.sliceExcerpt(
          text,
          minChars: 300,
          maxChars: 600,
          random: Random(seed),
        );
        expect(excerpt.length, greaterThanOrEqualTo(240));
        expect(excerpt.length, lessThanOrEqualTo(620));
        expect(excerpt.trim(), excerpt);
        expect(excerpt.startsWith('第'), isTrue);
      }
    });

    test('整篇超长且无空行时按句号切分，不腰斩段落开头', () {
      final String text = List<String>.generate(
        40,
        (int i) => '这是第$i句，用来验证句子边界切分是否正确。',
      ).join();
      final String excerpt =
          TextCleaner.sliceExcerpt(text, random: Random(3));
      expect(excerpt.length, greaterThanOrEqualTo(240));
      expect(excerpt.length, lessThanOrEqualTo(620));
      expect(excerpt.endsWith('。'), isTrue);
    });

    test('极短文本直接返回全文', () {
      const String short = '世间珍果更无加，玉雪肌肤罩绛纱。';
      expect(TextCleaner.sliceExcerpt(short, random: Random(1)), short);
    });
  });
}
