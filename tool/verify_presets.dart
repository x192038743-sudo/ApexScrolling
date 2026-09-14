// 预置书单体检：逐篇确认「页面存在 + 有正文 + 不是目录页」。
//
//   dart run tool/verify_presets.dart
//
// 输出每篇的长度与判定，并把报告写到 build/presets_report.txt。
// 判定为「目录/无正文/过短」的条目应当从 presets.dart 里删除。
import 'dart:io';
import 'dart:convert';

import 'package:apex_scrolling/core/endpoints.dart';
import 'package:apex_scrolling/data/adapters/mediawiki_client.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/data/presets.dart';
import 'package:apex_scrolling/data/text_cleaner.dart';

Future<void> main() async {
  final NetClient net = NetClient();
  final MediaWikiClient client =
      MediaWikiClient(net, apiUrl: Endpoints.wikisourceApi);

  final List<({String group, WikisourceWork work})> all =
      <({String group, WikisourceWork work})>[
    for (final WikisourceWork work in classicWorksZh)
      (group: '经典', work: work),
    for (final WikisourceWork work in proseWorksZh)
      (group: '散文小说', work: work),
  ];

  final StringBuffer report = StringBuffer();
  final List<String> rejected = <String>[];
  var ok = 0;

  for (final ({String group, WikisourceWork work}) item in all) {
    String verdict;
    try {
      final String text = await client.fetchPlainText(item.work.title);
      if (text.isEmpty) {
        verdict = '剔除：页面不存在或无正文';
      } else if (text.length < 400) {
        verdict = '剔除：正文过短(${text.length}字)';
      } else if (TextCleaner.looksLikeIndex(text)) {
        verdict = '剔除：像目录页(${text.length}字)';
      } else {
        verdict = '保留：${text.length} 字';
        ok++;
      }
    } catch (error) {
      verdict = '剔除：抓取失败($error)';
    }
    if (verdict.startsWith('剔除')) {
      rejected.add('${item.group}｜${item.work.title}：$verdict');
    }
    final String line =
        '${item.group.padRight(5)}｜${item.work.display.padRight(14)}｜'
        '${item.work.title.padRight(24)}｜$verdict';
    report.writeln(line);
    stdout.writeln(line);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  report
    ..writeln('')
    ..writeln('合计 ${all.length} 篇，保留 $ok 篇，剔除 ${rejected.length} 篇：');
  for (final String reason in rejected) {
    report.writeln('  - $reason');
  }

  final Directory outDir = Directory('build');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  await File('build/presets_report.txt')
      .writeAsString(report.toString(), encoding: utf8);
  stdout.writeln('报告：build/presets_report.txt');
}
