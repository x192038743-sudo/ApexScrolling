import 'package:apex_scrolling/data/adapters/poetry_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

void main() {
  test('今日诗词返回诗句 + 出处', () async {
    final PoetryAdapter adapter = PoetryAdapter(
      NetClient(
        client: MockClient(
          (http.Request request) async => jsonResponse(fixture('poetry.json')),
        ),
      ),
    );
    final TextCard card = await adapter.fetch();

    expect(card.kind, CardKind.poetry);
    expect(card.title, '咏荔枝');
    expect(card.subtitle, '丘浚 · 今日诗词');
    expect(card.body, '世间珍果更无加，玉雪肌肤罩绛纱。');
    expect(card.attribution, '今日诗词');
  });

  test('接口返回空内容时抛 SourceException', () async {
    final PoetryAdapter adapter = PoetryAdapter(
      NetClient(
        client: MockClient(
          (http.Request request) async => jsonResponse('{"content":""}'),
        ),
      ),
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });
}
