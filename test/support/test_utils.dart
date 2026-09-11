import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 读取 `test/fixtures` 下的固定数据。
String fixture(String name) =>
    File('${Directory.current.path}/test/fixtures/$name').readAsStringSync();

/// 统一用 UTF-8 字节构造响应，避免 package:http 默认 latin1 编码中文。
http.Response jsonResponse(String body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

http.Response htmlResponse(String body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: <String, String>{
        'content-type': 'text/html; charset=utf-8',
      },
    );

http.Response textResponse(String body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: <String, String>{
        'content-type': 'text/plain; charset=utf-8',
      },
    );

http.Response emptyResponse({int status = 500}) =>
    http.Response.bytes(const <int>[], status);
