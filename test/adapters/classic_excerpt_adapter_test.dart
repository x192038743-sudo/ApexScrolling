import 'dart:convert';
import 'dart:math';

import 'package:apex_scrolling/data/adapters/classic_excerpt_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

/// 古登堡书目 JSON（单本）。
String bookJson(int id, String title, String author, String textUrl) =>
    jsonEncode(<String, dynamic>{
      'id': id,
      'title': title,
      'authors': <Map<String, String>>[
        <String, String>{'name': author},
      ],
      'formats': <String, String>{
        'text/plain; charset=utf-8': textUrl,
      },
    });

void main() {
  group('中文经典（维基文库）', () {
    test('随机抽书 → 300–600 字段落选段', () async {
      final ClassicExcerptAdapter adapter = ClassicExcerptAdapter(
        NetClient(
          client: MockClient((http.Request request) async {
            if (request.url.host == 'zh.wikisource.org') {
              return jsonResponse(fixture('wikisource_parse.json'));
            }
            return emptyResponse(status: 500);
          }),
        ),
        random: Random(2),
      );
      final TextCard card = await adapter.fetch();

      expect(card.kind, CardKind.classicExcerpt);
      expect(card.attribution, contains('维基文库'));
      expect(card.body.length, greaterThan(120));
      // 选段来自清洗后的文库正文（页眉/姊妹项目等版式残留已被剔除）。
      expect(card.body, isNot(contains('姊妹计划')));
      expect(card.body, isNot(contains('吶喊自序')));
      expect(card.subtitle, contains('· 维基文库'));
      expect(card.sourceUrl, contains('zh.wikisource.org'));
    });
  });

  group('英文经典（古登堡计划）', () {
    test('预置编号 → 下载全文 → 清洗去掉项目说明', () async {
      final ClassicExcerptAdapter adapter = ClassicExcerptAdapter(
        NetClient(
          client: MockClient((http.Request request) async {
            if (request.url.host == 'gutendex.com') {
              return jsonResponse(
                bookJson(
                  2680,
                  'Meditations',
                  'Marcus Aurelius',
                  'https://www.gutenberg.org/files/2680/2680-0.txt',
                ),
              );
            }
            if (request.url.host == 'www.gutenberg.org') {
              return textResponse(fixture('gutenberg_text.txt'));
            }
            return emptyResponse(status: 500);
          }),
        ),
        random: Random(4),
      );
      final TextCard card = await adapter.fetch();

      expect(card.attribution, contains('古登堡计划'));
      expect(card.title, 'Meditations');
      expect(card.subtitle, contains('Marcus Aurelius'));
      expect(card.body, isNot(contains('PROJECT GUTENBERG')));
      expect(card.body.length, greaterThan(80));
    });
  });

  test('两个来源都不可用时抛 SourceException', () async {
    final ClassicExcerptAdapter adapter = ClassicExcerptAdapter(
      NetClient(
        client: MockClient((http.Request request) async => emptyResponse()),
      ),
      random: Random(1),
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });
}
