import 'dart:math';

import 'package:apex_scrolling/data/adapters/howto_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

void main() {
  test('wikiHow：随机条目 → 编号步骤卡（子步骤不入卡）', () async {
    final HowToAdapter adapter = HowToAdapter(
      NetClient(
        client: MockClient((http.Request request) async {
          if (request.url.host.contains('wikihow.com')) {
            if (request.url.queryParameters['list'] == 'random') {
              return jsonResponse(fixture('wikihow_random.json'));
            }
            return jsonResponse(fixture('wikihow_revision.json'));
          }
          return emptyResponse(status: 500);
        }),
      ),
      random: Random(1),
    );
    final TextCard card = await adapter.fetch();

    expect(card.kind, CardKind.howTo);
    expect(card.title, '如何更有效地学习');
    expect(card.steps, hasLength(5));
    expect(card.steps.first, contains('25 分钟'));
    expect(card.steps.any((String s) => s.contains('二级子步骤')), isFalse);
    expect(card.body, contains('学习效率'));
    expect(card.attribution, contains('CC BY-NC-SA'));
    // 展开态合成编号步骤。
    expect(card.fullText, contains('1. 把学习内容拆成'));
  });

  test('wikiHow 不可达时退回维基教科书', () async {
    final HowToAdapter adapter = HowToAdapter(
      NetClient(
        client: MockClient((http.Request request) async {
          if (request.url.host.contains('wikihow.com')) {
            return emptyResponse(status: 500);
          }
          if (request.url.host == 'zh.wikibooks.org') {
            final String? list = request.url.queryParameters['list'];
            if (list == 'search' || list == 'prefixsearch') {
              final String key = list == 'search' ? 'search' : 'prefixsearch';
              return jsonResponse(
                '{"query":{"$key":['
                '{"ns":0,"title":"食谱/番茄炒蛋","pageid":1001},'
                '{"ns":0,"title":"食谱/蛋炒饭","pageid":1002}]}}',
              );
            }
            return jsonResponse(fixture('wikibooks_parse.json'));
          }
          return emptyResponse(status: 500);
        }),
      ),
      random: Random(2),
    );
    final TextCard card = await adapter.fetch();

    expect(card.attribution, contains('维基教科书'));
    expect(card.steps, hasLength(4));
    expect(card.body, isNotEmpty);
  });

  test('所有技能源不可用时抛 SourceException', () async {
    final HowToAdapter adapter = HowToAdapter(
      NetClient(
        client: MockClient((http.Request request) async => emptyResponse()),
      ),
      random: Random(1),
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });
}
