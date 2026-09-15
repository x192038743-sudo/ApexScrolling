import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/data/translation_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('双击单词翻译只解析首个译文片段', () async {
    final TranslationClient client = TranslationClient(
      NetClient(
        client: MockClient((http.Request request) async {
          expect(request.url.host, 'translate.googleapis.com');
          expect(request.url.queryParameters['q'], 'ephemeral');
          return http.Response(
            '[[["短暂的","ephemeral",null,null,1]],null,"en"]',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
    );

    expect(await client.translateWord('ephemeral'), '短暂的');
  });

  test('翻译拒绝句子和超长输入', () async {
    final TranslationClient client = TranslationClient(
      NetClient(
        client: MockClient((http.Request request) async {
          return http.Response('[]', 200);
        }),
      ),
    );
    expect(
      client.translateWord('hello world'),
      throwsA(isA<SourceException>()),
    );
    expect(client.translateWord('a' * 65), throwsA(isA<SourceException>()));
  });
}
