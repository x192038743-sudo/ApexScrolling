import 'dart:math';

import 'package:apex_scrolling/data/adapters/prose_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';
import 'classic_excerpt_adapter_test.dart' show bookJson;

void main() {
  test('中文散文：维基文库 → 完整场景片段', () async {
    final ProseAdapter adapter = ProseAdapter(
      NetClient(
        client: MockClient((http.Request request) async {
          if (request.url.host == 'zh.wikisource.org') {
            return jsonResponse(fixture('wikisource_parse.json'));
          }
          return emptyResponse(status: 500);
        }),
      ),
      random: Random(6),
    );
    final TextCard card = await adapter.fetch();
    expect(card.kind, CardKind.prose);
    expect(card.attribution, contains('维基文库'));
    expect(card.body.length, greaterThan(80));
  });

  test('英文短篇：按作者检索后随机取一篇', () async {
    final ProseAdapter adapter = ProseAdapter(
      NetClient(
        client: MockClient((http.Request request) async {
          if (request.url.host == 'gutendex.com' &&
              request.url.path.contains('/books/')) {
            return jsonResponse(
              bookJson(
                108,
                'The Lady with the Dog',
                'Anton Chekhov',
                'https://www.gutenberg.org/files/108/108-0.txt',
              ),
            );
          }
          if (request.url.host == 'gutendex.com') {
            // 检索结果按作者返回契诃夫的作品。
            return jsonResponse(
              '{"count":1,"results":['
              '{"id":108,"title":"The Lady with the Dog",'
              '"authors":[{"name":"Anton Chekhov"}],'
              '"formats":{"text/plain; charset=utf-8":'
              '"https://www.gutenberg.org/files/108/108-0.txt"}}]}',
            );
          }
          if (request.url.host == 'www.gutenberg.org') {
            return textResponse(fixture('gutenberg_text.txt'));
          }
          return emptyResponse(status: 500);
        }),
      ),
      random: Random(8),
    );
    final TextCard card = await adapter.fetch(preferEnglish: true);
    expect(card.attribution, contains('古登堡计划'));
    expect(card.subtitle, contains('Anton Chekhov'));
    expect(card.body.length, greaterThan(80));
  });
}
