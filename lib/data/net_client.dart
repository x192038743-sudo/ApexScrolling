import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/endpoints.dart';

/// 数据源请求失败（供信息流做换源重抽与熔断）。
class SourceException implements Exception {
  SourceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SourceException($statusCode): $message';
}

/// 轻量 HTTP 封装：统一 UA、超时、JSON 解析与错误类型。
class NetClient {
  NetClient({http.Client? client, Map<String, String>? defaultHeaders})
      : _client = client ?? http.Client(),
        _defaultHeaders = defaultHeaders ?? const <String, String>{};

  final http.Client _client;
  final Map<String, String> _defaultHeaders;

  Map<String, String> _headers(Map<String, String>? extra) =>
      <String, String>{
        'User-Agent': _ascii(Endpoints.userAgent),
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        for (final MapEntry<String, String> entry in _defaultHeaders.entries)
          entry.key: _ascii(entry.value),
        if (extra != null)
          for (final MapEntry<String, String> entry in extra.entries)
            entry.key: _ascii(entry.value),
      };

  /// HTTP 头只接受 ASCII：这里兜底剔除越界字符，避免个别数据源
  /// 或本地化文案把中文写进请求头导致整个请求失败。
  static String _ascii(String value) {
    if (!value.codeUnits.any((int unit) => unit > 0x7F)) return value;
    return value.codeUnits
        .where((int unit) => unit <= 0x7F)
        .map(String.fromCharCode)
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String> getText(
    Uri uri, {
    Duration timeout = NetPolicy.requestTimeout,
    Map<String, String>? headers,
  }) async {
    final http.Response response =
        await _send(() => _client.get(uri, headers: _headers(headers)),
            timeout: timeout);
    _ensureOk(response, uri);
    return decodeBody(response);
  }

  Future<List<int>> getBytes(
    Uri uri, {
    Duration timeout = NetPolicy.downloadTimeout,
    Map<String, String>? headers,
  }) async {
    final http.Response response =
        await _send(() => _client.get(uri, headers: _headers(headers)),
            timeout: timeout);
    _ensureOk(response, uri);
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Duration timeout = NetPolicy.requestTimeout,
    Map<String, String>? headers,
  }) async {
    final http.Response response =
        await _send(() => _client.get(uri, headers: _headers(headers)),
            timeout: timeout);
    _ensureOk(response, uri);
    return _decodeJson(response);
  }

  /// SPARQL 查询：POST form 提交，避免超长 URL 被截断。
  Future<Map<String, dynamic>> postSparql(
    Uri uri,
    String query, {
    Duration timeout = NetPolicy.sparqlTimeout,
  }) async {
    final http.Response response = await _send(
      () => _client.post(
        uri,
        headers: _headers(<String, String>{
          'Accept': 'application/sparql-results+json',
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        }),
        body: <String, String>{'query': query},
      ),
      timeout: timeout,
    );
    _ensureOk(response, uri);
    return _decodeJson(response);
  }

  void close() => _client.close();

  Future<http.Response> _send(
    Future<http.Response> Function() action, {
    required Duration timeout,
  }) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw SourceException('请求超时（${timeout.inSeconds}s）');
    } on SourceException {
      rethrow;
    } catch (error) {
      throw SourceException('网络请求失败：$error');
    }
  }

  void _ensureOk(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw SourceException(
      'HTTP ${response.statusCode} (${uri.host})',
      statusCode: response.statusCode,
    );
  }

  static String decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return '';
    // 优先按响应头里的字符集，其次按 UTF-8 处理。
    final String? contentType = response.headers['content-type'];
    if (contentType != null) {
      final RegExpMatch? match =
          RegExp(r'charset=([\w-]+)', caseSensitive: false)
              .firstMatch(contentType);
      final String? charset = match?.group(1)?.toLowerCase();
      if (charset != null && charset != 'utf-8' && charset != 'utf8') {
        try {
          return _decodeWith(charset, response.bodyBytes);
        } on ArgumentError {
          // 未知字符集：退回 UTF-8。
        }
      }
    }
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return latin1.decode(response.bodyBytes);
    }
  }

  static String _decodeWith(String charset, List<int> bytes) {
    const Map<String, String> aliases = <String, String>{
      'iso-8859-1': 'latin1',
      'us-ascii': 'ascii',
      'ascii': 'ascii',
      'utf-8': 'utf8',
      'utf8': 'utf8',
      'latin1': 'latin1',
    };
    final String codec = aliases[charset] ?? charset;
    switch (codec) {
      case 'utf8':
        return utf8.decode(bytes);
      case 'latin1':
        return latin1.decode(bytes);
      case 'ascii':
        return ascii.decode(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    final String body = decodeBody(response);
    if (body.trim().isEmpty) {
      throw SourceException('响应为空');
    }
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw SourceException('响应格式非对象');
    } on FormatException catch (error) {
      throw SourceException('JSON 解析失败：${error.message}');
    }
  }
}
