import 'dart:convert';
import 'dart:math';

import 'package:apex_scrolling/data/adapters/poetry_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_utils.dart';

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this._values);

  final Map<String, String> _values;

  @override
  Future<ByteData> load(String key) async {
    final String? value = _values[key];
    if (value == null) throw StateError('asset not found: $key');
    final Uint8List bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.view(bytes.buffer);
  }
}

void main() {
  test('今日诗词返回诗句 + 出处', () async {
    final PoetryAdapter adapter = PoetryAdapter(
      NetClient(
        client: MockClient(
          (http.Request request) async => jsonResponse(fixture('poetry.json')),
        ),
      ),
      useBundledPoems: false,
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
      useBundledPoems: false,
    );
    expect(adapter.fetch(), throwsA(isA<SourceException>()));
  });

  test('优先使用随包的完整诗词，不再只显示一句', () async {
    const String asset =
        '{"collection":"测试选集","poems":['
        '{"title":"静夜思","author":"李白",'
        '"lines":["床前明月光，疑是地上霜。",'
        '"举头望明月，低头思故乡。"]},'
        '{"title":"春晓","author":"孟浩然",'
        '"lines":["春眠不觉晓，处处闻啼鸟。",'
        '"夜来风雨声，花落知多少。"]}]}';
    final PoetryAdapter adapter = PoetryAdapter(
      NetClient(
        client: MockClient(
          (http.Request request) async => jsonResponse(fixture('poetry.json')),
        ),
      ),
      bundle: _MemoryAssetBundle(<String, String>{
        'assets/poems/tangshi.json': asset,
      }),
      random: Random(1),
    );

    final TextCard first = await adapter.fetch();
    final TextCard second = await adapter.fetch();
    expect(first.body.split('\n'), hasLength(2));
    expect(first.attribution, contains('维基文库'));
    expect(first.id, isNot(second.id));
  });

  testWidgets('默认构造会读取随包诗词资产', (WidgetTester tester) async {
    final PoetryAdapter adapter = PoetryAdapter(
      NetClient(
        client: MockClient(
          (http.Request request) async => jsonResponse('{"content":""}'),
        ),
      ),
    );
    final TextCard card = await adapter.fetch();
    expect(card.body, contains('\n'));
    expect(card.attribution, contains('维基文库'));
  });
}
