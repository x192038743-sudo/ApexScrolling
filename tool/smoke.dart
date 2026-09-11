// 真实网络冒烟脚本：直接跑六个适配器，确认线上数据可用。
//
//   dart run tool/smoke.dart
//
// 输出每张卡片的耗时、标题、正文字数与署名，用于验收前自检。
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:apex_scrolling/data/adapters/card_adapter.dart';
import 'package:apex_scrolling/data/adapters/classic_excerpt_adapter.dart';
import 'package:apex_scrolling/data/adapters/howto_adapter.dart';
import 'package:apex_scrolling/data/adapters/philosophy_adapter.dart';
import 'package:apex_scrolling/data/adapters/poetry_adapter.dart';
import 'package:apex_scrolling/data/adapters/prose_adapter.dart';
import 'package:apex_scrolling/data/adapters/wiki_term_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';

Future<void> main() async {
  final NetClient net = NetClient();
  final Random rng = Random(2026);
  final AppSettings settings = const AppSettings();
  final Map<String, CardAdapter> adapters = <String, CardAdapter>{
    '冷门学术词条': WikiTermAdapter(net, settings, random: rng),
    '哲学观点(SEP)': PhilosophyAdapter(net, random: rng),
    '经典选段': ClassicExcerptAdapter(net, random: rng),
    '短篇/散文': ProseAdapter(net, random: rng),
    '实用技能': HowToAdapter(net, random: rng),
    '诗词名句': PoetryAdapter(net),
  };

  final StringBuffer report = StringBuffer();
  var ok = 0;
  for (final MapEntry<String, CardAdapter> entry in adapters.entries) {
    final Stopwatch watch = Stopwatch()..start();
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final TextCard card = await entry.value.fetch();
          watch.stop();
          ok++;
          final String flat = card.body.replaceAll('\n', ' ');
          final String preview = flat.substring(0, min(90, flat.length));
          report
            ..writeln('[OK]   ${entry.key}  ${watch.elapsedMilliseconds}ms')
            ..writeln('       标题: ${card.title}')
            ..writeln('       署名: ${card.attribution}')
            ..writeln('       正文(${card.body.length}字): $preview…');
          if (card.steps.isNotEmpty) {
            report.writeln('       步骤: ${card.steps.length} 条');
          }
          if (card.links.isNotEmpty) {
            report.writeln(
              '       内链: ${card.links.map((CardLink l) => l.label).join(' / ')}',
            );
          }
          break;
        } catch (error) {
          if (attempt == 2) rethrow;
          report.writeln('[重试] ${entry.key}: $error');
        }
      }
    } catch (error) {
      watch.stop();
      report.writeln(
          '[FAIL] ${entry.key}  ${watch.elapsedMilliseconds}ms  $error');
    }
    report.writeln('');
  }
  report.writeln('结果: $ok/${adapters.length} 个数据源可用');

  stdout.write(report);
  final Directory outDir = Directory('build');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  await File('build/smoke_report.txt')
      .writeAsString(report.toString(), encoding: utf8);
}
