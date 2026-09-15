import 'dart:convert';

import 'package:apex_scrolling/core/endpoints.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_utils.dart';

void main() {
  test('请求头只包含 ASCII（中文 User-Agent 会直接导致请求失败）', () async {
    late Map<String, String> captured;
    final NetClient client = NetClient(
      client: MockClient((http.Request request) async {
        captured = request.headers;
        return jsonResponse('{"ok":true}');
      }),
      defaultHeaders: <String, String>{'X-Note': '纯文字阅读'},
    );

    await client.getJson(Uri.parse('https://example.com/api'));

    for (final MapEntry<String, String> entry in captured.entries) {
      expect(
        entry.value.codeUnits.every((int unit) => unit <= 0x7F),
        isTrue,
        reason: '请求头 ${entry.key} 含非 ASCII 字符：${entry.value}',
      );
    }
    expect(captured['user-agent'], startsWith('ApexScrolling/'));
    expect(captured['user-agent'], isNot(contains(RegExp(r'[^\x00-\x7F]'))));
    expect(Endpoints.userAgent.codeUnits.every((int u) => u <= 0x7F), isTrue);
  });

  test('HTTP 错误映射为 SourceException 并保留状态码', () async {
    final NetClient client = NetClient(
      client: MockClient(
        (http.Request request) async => emptyResponse(status: 503),
      ),
    );
    await expectLater(
      client.getText(Uri.parse('https://example.com/x')),
      throwsA(
        isA<SourceException>().having(
          (SourceException e) => e.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('非 UTF-8 响应按字符集解码', () async {
    final List<int> latin1Bytes = latin1.encode('Café');
    final NetClient client = NetClient(
      client: MockClient(
        (http.Request request) async => http.Response.bytes(
          latin1Bytes,
          200,
          headers: <String, String>{
            'content-type': 'text/plain; charset=iso-8859-1',
          },
        ),
      ),
    );
    expect(await client.getText(Uri.parse('https://example.com/x')), 'Café');
  });

  test('SPARQL 用 POST 提交 query', () async {
    late http.Request captured;
    final NetClient client = NetClient(
      client: MockClient((http.Request request) async {
        captured = request;
        return jsonResponse('{"results":{"bindings":[]}}');
      }),
    );
    await client.postSparql(
      Uri.parse('https://query.wikidata.org/sparql'),
      'SELECT * WHERE { ?s ?p ?o } LIMIT 1',
    );
    expect(captured.method, 'POST');
    expect(captured.body, contains('SELECT'));
    expect(captured.headers['accept'], contains('sparql-results+json'));
  });
}
