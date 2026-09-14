import 'dart:math';

import 'package:apex_scrolling/data/adapters/wiki_term_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

void main() {
  late List<String> requestedHosts;

  MockClient buildClient() => MockClient((http.Request request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == 'query.wikidata.org') {
          return jsonResponse(fixture('sparql_candidates.json'));
        }
        if (request.url.host == 'api.wikimedia.org') {
          return htmlResponse(fixture('wiki_article_zh.html'));
        }
        return emptyResponse(status: 404);
      });

  setUp(() => requestedHosts = <String>[]);

  test('SPARQL 查候选 + 拉取条目导语，生成词条卡', () async {
    final WikiTermAdapter adapter = WikiTermAdapter(
      NetClient(client: buildClient()),
      const AppSettings(),
      random: Random(7),
    );
    final TextCard card = await adapter.fetch();

    expect(requestedHosts, contains('query.wikidata.org'));
    expect(requestedHosts, contains('api.wikimedia.org'));
    expect(card.kind, CardKind.wikiTerm);
    expect(card.title, '二项式定理');
    // 候选池里中英文条目都可能被抽到，署名需标明语言版本。
    expect(card.subtitle, startsWith('维基百科 · '));
    expect(card.attribution, contains('CC BY-SA'));
    expect(card.body, contains('二项式定理'));
    // 只取导语：第一个小节标题之后的段落不进入卡片。
    expect(card.body, isNot(contains('必须被忽略')));
    expect(card.depth, 0);
    // 内链用于兔子洞。
    expect(
      card.links.map((CardLink link) => link.title),
      contains('组合数'),
    );
    expect(card.sourceUrl, contains('.wikipedia.org/wiki/'));
  });

  test('英文模式下，严格档（≤20）跳过站点链接数超标的候选', () async {
    final WikiTermAdapter adapter = WikiTermAdapter(
      NetClient(client: buildClient()),
      const AppSettings(wikiRarity: WikiRarity.strict),
      random: Random(3),
    );
    final TextCard card = await adapter.fetch(preferEnglish: true);
    // 只有英文候选（18 个站点链接）满足严格阈值。
    expect(card.subtitle, '维基百科 · 英文');
  });

  test('fetchByTitle 支持兔子洞深度与内链', () async {
    final WikiTermAdapter adapter = WikiTermAdapter(
      NetClient(client: buildClient()),
      const AppSettings(),
      random: Random(1),
    );
    final TextCard card = await adapter.fetchByTitle(
      '组合数',
      depth: 2,
      subtitleLabel: '组合数',
    );
    expect(card.depth, 2);
    expect(card.canDigDeeper, isTrue);
    expect(card.id, contains('组合数'));
  });

  test('内容源失败时抛出 SourceException（供换源重抽）', () async {
    final WikiTermAdapter adapter = WikiTermAdapter(
      NetClient(
        client: MockClient((http.Request request) async => emptyResponse()),
      ),
      const AppSettings(),
      random: Random(1),
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });
}
