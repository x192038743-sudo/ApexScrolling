import 'dart:convert';

import 'net_client.dart';

/// 轻量单词翻译客户端。仅在用户双击英文单词时请求，不上传整篇正文。
class TranslationClient {
  TranslationClient(this._net);

  final NetClient _net;

  Future<String> translateWord(String word, {String target = 'zh-CN'}) async {
    final String normalized = word.trim();
    if (!RegExp(r"^[A-Za-z][A-Za-z'’-]{0,63}$").hasMatch(normalized)) {
      throw SourceException('请选择一个英文单词');
    }
    final Uri uri = Uri.https(
      'translate.googleapis.com',
      '/translate_a/single',
      <String, String>{
        'client': 'gtx',
        'sl': 'auto',
        'tl': target,
        'dt': 't',
        'q': normalized,
      },
    );
    final String raw = await _net.getText(uri);
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
      throw SourceException('翻译结果为空');
    }
    final List<dynamic> segments = decoded.first as List<dynamic>;
    final String result = segments
        .whereType<List<dynamic>>()
        .map(
          (List<dynamic> segment) => segment.isEmpty ? '' : '${segment.first}',
        )
        .join()
        .trim();
    if (result.isEmpty) throw SourceException('翻译结果为空');
    return result;
  }
}
