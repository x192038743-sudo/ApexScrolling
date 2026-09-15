import 'dart:math';

import 'package:apex_scrolling/data/adapters/philosophy_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

void main() {
  MockClient buildClient() => MockClient((http.Request request) async {
    if (request.url.path.endsWith('/contents.html')) {
      return htmlResponse(fixture('sep_contents.html'));
    }
    if (request.url.path.contains('/entries/')) {
      return htmlResponse(fixture('sep_entry.html'));
    }
    return emptyResponse(status: 404);
  });

  test('抓取 SEP 目录并解析条目导语', () async {
    final PhilosophyAdapter adapter = PhilosophyAdapter(
      NetClient(client: buildClient()),
      random: Random(5),
    );
    final TextCard card = await adapter.fetch(preferEnglish: true);

    expect(card.kind, CardKind.philosophy);
    expect(card.title, 'Virtue Ethics');
    expect(card.subtitle, contains('Stanford'));
    expect(card.body, contains('three major approaches'));
    expect(card.body, contains('Aristotle'));
    // 标题之后的段落不进入导语。
    expect(card.body, isNot(contains('must be ignored')));
    expect(card.links, isEmpty);
    expect(card.sourceUrl, contains('/entries/'));
  });

  test('目录不可用时抛 SourceException', () async {
    final PhilosophyAdapter adapter = PhilosophyAdapter(
      NetClient(
        client: MockClient((http.Request request) async => emptyResponse()),
      ),
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });
}
