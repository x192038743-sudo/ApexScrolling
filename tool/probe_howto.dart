// 抽样式体检「实用技能」源：连续抓 N 张，打印标题与步骤数，用来判断质量。
//
//   dart run tool/probe_howto.dart [次数]
import 'dart:io';

import 'package:apex_scrolling/data/adapters/howto_adapter.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/text_card.dart';

Future<void> main(List<String> args) async {
  final int times = int.tryParse(args.isEmpty ? '' : args.first) ?? 8;
  final NetClient net = NetClient();
  final HowToAdapter adapter = HowToAdapter(net);

  var ok = 0;
  for (var i = 1; i <= times; i++) {
    try {
      final TextCard card = await adapter.fetch();
      ok++;
      stdout.writeln(
        '${i.toString().padLeft(2)}. [${card.attribution}] ${card.title}'
        ' | 步骤 ${card.steps.length} | 正文 ${card.body.length} 字',
      );
    } catch (error) {
      stdout.writeln('${i.toString().padLeft(2)}. [失败] $error');
    }
  }
  stdout.writeln('成功 $ok/$times');
}
