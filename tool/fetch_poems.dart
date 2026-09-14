// 生成内置诗词选集：从中文维基文库逐篇抓取公版诗词，输出到 assets/poems/。
//
//   dart run tool/fetch_poems.dart
//
// 每篇会：取渲染 HTML → 提取标题/作者/正文 → 剔除消歧义与目录页 →
// 校验正文像"诗/词"（分行为主、含诗词标点）→ 写入 JSON。
// 报告写到 build/poems_report.txt，被剔除的条目会列出原因。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:apex_scrolling/core/endpoints.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/data/text_cleaner.dart';

/// 候选篇目：(文库页面名, 选集归属)。
const List<(String, String)> candidates = <(String, String)>[
  // ---------------------------------------------------------------- 唐詩
  ('靜夜思', '唐詩選'), ('春曉 (孟浩然)', '唐詩選'), ('登鸛雀樓 (王之渙)', '唐詩選'),
  ('楓橋夜泊', '唐詩選'), ('相思 (王維)', '唐詩選'), ('鹿柴', '唐詩選'),
  ('山居秋暝', '唐詩選'), ('送元二使安西', '唐詩選'), ('九月九日憶山東兄弟', '唐詩選'),
  ('竹里館', '唐詩選'), ('鳥鳴澗', '唐詩選'), ('使至塞上', '唐詩選'),
  ('終南別業', '唐詩選'), ('雜詩 (王維)', '唐詩選'), ('過故人莊', '唐詩選'),
  ('宿建德江', '唐詩選'), ('望廬山瀑布', '唐詩選'), ('早發白帝城', '唐詩選'),
  ('贈汪倫', '唐詩選'), ('獨坐敬亭山', '唐詩選'), ('望天門山', '唐詩選'),
  ('夜宿山寺', '唐詩選'), ('客中行', '唐詩選'), ('月下獨酌', '唐詩選'),
  ('將進酒', '唐詩選'), ('黃鶴樓送孟浩然之廣陵', '唐詩選'), ('秋浦歌', '唐詩選'),
  ('峨眉山月歌', '唐詩選'), ('宣州謝朓樓餞別校書叔雲', '唐詩選'), ('春望', '唐詩選'),
  ('望嶽', '唐詩選'), ('江畔獨步尋花', '唐詩選'), ('登高 (杜甫)', '唐詩選'),
  ('春夜喜雨', '唐詩選'), ('月夜憶舍弟', '唐詩選'), ('江南逢李龜年', '唐詩選'),
  ('蜀相', '唐詩選'), ('八陣圖', '唐詩選'), ('石壕吏', '唐詩選'),
  ('茅屋為秋風所破歌', '唐詩選'), ('聞官軍收河南河北', '唐詩選'), ('旅夜書懷', '唐詩選'),
  ('憫農', '唐詩選'), ('江雪', '唐詩選'), ('漁翁', '唐詩選'),
  ('登柳州城樓寄漳汀封連四州', '唐詩選'), ('烏衣巷', '唐詩選'), ('竹枝詞', '唐詩選'),
  ('秋詞', '唐詩選'), ('望洞庭', '唐詩選'), ('賦得古原草送別', '唐詩選'),
  ('大林寺桃花', '唐詩選'), ('暮江吟', '唐詩選'), ('錢塘湖春行', '唐詩選'),
  ('琵琶行', '唐詩選'), ('長恨歌', '唐詩選'), ('無題 (李商隱)', '唐詩選'),
  ('錦瑟', '唐詩選'), ('夜雨寄北', '唐詩選'), ('嫦娥 (李商隱)', '唐詩選'),
  ('樂遊原', '唐詩選'), ('賈生', '唐詩選'), ('泊秦淮', '唐詩選'),
  ('山行 (杜牧)', '唐詩選'), ('清明 (杜牧)', '唐詩選'), ('江南春 (杜牧)', '唐詩選'),
  ('赤壁 (杜牧)', '唐詩選'), ('題烏江亭', '唐詩選'), ('過華清宮', '唐詩選'),
  ('秋夕', '唐詩選'), ('遣懷', '唐詩選'), ('出塞 (王昌齡)', '唐詩選'),
  ('從軍行 (王昌齡)', '唐詩選'), ('芙蓉樓送辛漸', '唐詩選'), ('閨怨', '唐詩選'),
  ('涼州詞 (王翰)', '唐詩選'), ('涼州詞 (王之渙)', '唐詩選'), ('登幽州臺歌', '唐詩選'),
  ('春江花月夜', '唐詩選'), ('遊子吟', '唐詩選'), ('尋隱者不遇', '唐詩選'),
  ('題詩後', '唐詩選'), ('劍客', '唐詩選'), ('塞下曲 (盧綸)', '唐詩選'),
  ('秋思 (張籍)', '唐詩選'), ('題都城南莊', '唐詩選'), ('金縷衣', '唐詩選'),
  ('回鄉偶書', '唐詩選'), ('詠柳', '唐詩選'), ('望月懷遠', '唐詩選'),
  ('別董大', '唐詩選'), ('白雪歌送武判官歸京', '唐詩選'), ('逢入京使', '唐詩選'),
  ('黃鶴樓 (崔顥)', '唐詩選'), ('題西林壁', '宋詩選'), ('飲湖上初晴後雨', '宋詩選'),
  ('惠崇春江晚景', '宋詩選'), ('春日 (朱熹)', '宋詩選'), ('觀書有感', '宋詩選'),
  ('小池', '宋詩選'), ('曉出淨慈寺送林子方', '宋詩選'), ('宿新市徐公店', '宋詩選'),
  ('元日 (王安石)', '宋詩選'), ('泊船瓜洲', '宋詩選'), ('梅花 (王安石)', '宋詩選'),
  ('登飛來峰', '宋詩選'), ('示兒', '宋詩選'), ('遊山西村', '宋詩選'),
  ('冬夜讀書示子聿', '宋詩選'), ('石灰吟', '明清詩選'), ('竹石', '明清詩選'),
  ('墨梅', '明清詩選'), ('己亥雜詩', '明清詩選'), ('村居 (高鼎)', '明清詩選'),
  // ---------------------------------------------------------------- 宋詞
  ('水調歌頭 (蘇軾)', '宋詞選'), ('念奴嬌·赤壁懷古', '宋詞選'),
  ('江城子·乙卯正月二十日夜記夢', '宋詞選'), ('定風波 (蘇軾)', '宋詞選'),
  ('卜算子·黃州定慧院寓居作', '宋詞選'), ('蝶戀花·春景', '宋詞選'),
  ('聲聲慢 (李清照)', '宋詞選'), ('如夢令 (李清照)', '宋詞選'), ('一剪梅 (李清照)', '宋詞選'),
  ('醉花陰 (李清照)', '宋詞選'), ('武陵春 (李清照)', '宋詞選'), ('漁家傲 (李清照)', '宋詞選'),
  ('青玉案·元夕', '宋詞選'), ('破陣子 (辛棄疾)', '宋詞選'), ('鷓鴣天 (辛棄疾)', '宋詞選'),
  ('西江月·夜行黃沙道中', '宋詞選'), ('永遇樂·京口北固亭懷古', '宋詞選'),
  ('醜奴兒·書博山道中壁', '宋詞選'), ('雨霖鈴 (柳永)', '宋詞選'),
  ('蝶戀花 (柳永)', '宋詞選'), ('望海潮 (柳永)', '宋詞選'), ('八聲甘州 (柳永)', '宋詞選'),
  ('虞美人 (李煜)', '宋詞選'), ('相見歡 (李煜)', '宋詞選'), ('浪淘沙令 (李煜)', '宋詞選'),
  ('滿江紅 (岳飛)', '宋詞選'), ('小重山 (岳飛)', '宋詞選'), ('揚州慢', '宋詞選'),
  ('蘇幕遮 (范仲淹)', '宋詞選'), ('漁家傲·秋思', '宋詞選'), ('踏莎行 (歐陽修)', '宋詞選'),
  ('采桑子 (歐陽修)', '宋詞選'), ('生查子·元夕', '宋詞選'), ('玉樓春 (宋祁)', '宋詞選'),
  ('鵲橋仙 (秦觀)', '宋詞選'), ('踏莎行 (秦觀)', '宋詞選'), ('卜算子·送鮑浩然之浙東', '宋詞選'),
  ('唐多令 (劉過)', '宋詞選'), ('一剪梅·舟過吳江', '宋詞選'), ('虞美人·聽雨', '宋詞選'),
  ('釵頭鳳 (陸游)', '宋詞選'), ('卜算子·詠梅', '宋詞選'),
];

/// `{{header}}` 模板里的 title / author 字段。
final RegExp _headerTitleRe = RegExp(r'\|\s*title\s*=\s*([^\n|}]+)');
final RegExp _headerAuthorRe = RegExp(r'\|\s*author\s*=\s*([^\n|}]+)');
/// 正文块：文库的诗页把干净正文放在 `<poem>` 里，其次是 `<onlyinclude>`。
final RegExp _poemBlockRe = RegExp(r'<poem>(.*?)</poem>', dotAll: true);
final RegExp _onlyIncludeRe =
    RegExp(r'<onlyinclude>(.*?)</onlyinclude>', dotAll: true);
final RegExp _disambigRe =
    RegExp(r'\{\{\s*(消歧義|消歧义|disambig|disambiguation)');

Future<void> main() async {
  final NetClient net = NetClient();
  final Directory outDir = Directory('assets/poems');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final Map<String, List<Map<String, dynamic>>> byCollection =
      <String, List<Map<String, dynamic>>>{};
  final List<String> rejected = <String>[];
  final Random rng = Random(2026);

  for (final (String page, String collection) in candidates) {
    try {
      final Uri uri = Uri.parse(Endpoints.wikisourceApi).replace(
        queryParameters: <String, String>{
          'action': 'parse',
          'format': 'json',
          'redirects': '1',
          'prop': 'wikitext',
          'page': page,
        },
      );
      final Map<String, dynamic> json = await net.getJson(uri);
      final Object? parse = json['parse'];
      if (parse is! Map<String, dynamic>) {
        rejected.add('$page：页面不存在');
        continue;
      }
      final Object? wikitext = (parse['wikitext'] as Map<String, dynamic>?)?['*'];
      if (wikitext is! String || wikitext.isEmpty) {
        rejected.add('$page：无内容');
        continue;
      }
      if (_disambigRe.hasMatch(wikitext)) {
        rejected.add('$page：消歧义页');
        continue;
      }
      final String title = _cleanTitle(
        _plainText(
          _headerValue(wikitext, _headerTitleRe) ??
              parse['title']?.toString() ??
              page,
        ),
      );
      final String author = _plainText(
        _headerValue(wikitext, _headerAuthorRe) ?? '',
      );
      final List<String> lines = _extractPoemLines(wikitext, title: title);
      final String body = lines.join('\n');
      // 诗词不参与目录判定（分行短句会被误判），改用诗词形状校验。
      if (author.isEmpty || !_looksLikePoem(lines)) {
        rejected.add('$page：正文不像诗词(${body.length}字/${lines.length}行)');
        continue;
      }
      byCollection.putIfAbsent(collection, () => <Map<String, dynamic>>[]).add(
        <String, dynamic>{
          'title': title,
          'author': author,
          'lines': lines,
        },
      );
    } catch (error) {
      rejected.add('$page：抓取失败($error)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  final StringBuffer report = StringBuffer();
  var total = 0;
  for (final MapEntry<String, List<Map<String, dynamic>>> entry
      in byCollection.entries) {
    final String slug = switch (entry.key) {
      '唐詩選' => 'tangshi',
      '宋詩選' => 'songshi',
      '明清詩選' => 'mingqing',
      _ => 'songci',
    };
    final List<Map<String, dynamic>> poems = entry.value..shuffle(rng);
    total += poems.length;
    final String path = 'assets/poems/$slug.json';
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'collection': entry.key,
        'poems': poems,
      }),
      encoding: utf8,
    );
    report.writeln('${entry.key} → $path：${poems.length} 首');
    stdout.writeln('${entry.key} → $path：${poems.length} 首');
  }
  report
    ..writeln('')
    ..writeln('合计 $total 首；剔除 ${rejected.length} 条：');
  for (final String reason in rejected) {
    report.writeln('  - $reason');
  }
  await File('build/poems_report.txt')
      .writeAsString(report.toString(), encoding: utf8);
  stdout.writeln('报告：build/poems_report.txt');
}

String? _headerValue(String wikitext, RegExp re) {
  final RegExpMatch? match = re.firstMatch(wikitext);
  final String? value = match?.group(1)?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

/// 把 wikitext 片段转成纯文本（去链接/模板/强调标记）。
String _plainText(String input) {
  var text = input;
  text = text.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
  text = text.replaceAllMapped(
    RegExp(r'\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]'),
    (Match m) => m.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r"'{2,}"), '');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  return TextCleaner.normalizeWhitespace(text);
}

/// 去掉文库标题里的消歧义后缀，如「登鸛雀樓 (王之渙)」→「登鸛雀樓」。
String _cleanTitle(String raw) {
  var title = TextCleaner.normalizeWhitespace(raw);
  title = title.replaceAll(RegExp(r'\s*[（(][^）)]{1,12}[）)]\s*$'), '');
  return title.trim();
}

/// 是否像一首诗词：分行短句、含诗词标点、没有超长行。
bool _looksLikePoem(List<String> lines) {
  if (lines.isEmpty || lines.length > 60) return false;
  final String body = lines.join('\n');
  if (body.length < 8 || body.length > 2000) return false;
  if (!RegExp(r'[，。！？、；]').hasMatch(body)) return false;
  if (lines.any((String line) => line.length > 60)) return false;
  return true;
}

/// 取诗词正文行：优先 `<poem>` 块，其次 `<onlyinclude>`，再退回全文。
List<String> _extractPoemLines(String wikitext, {required String title}) {
  final RegExpMatch? poem = _poemBlockRe.firstMatch(wikitext);
  final RegExpMatch? only = _onlyIncludeRe.firstMatch(wikitext);
  final String raw =
      poem?.group(1) ?? only?.group(1) ?? _stripHeaderTemplate(wikitext);

  final List<String> lines = <String>[];
  for (final String candidate in raw.split('\n')) {
    String line = _plainText(candidate);
    line = TextCleaner.stripCitationMarks(line).trim();
    if (line.isEmpty) continue;
    if (line == title) continue;
    if (RegExp(r'^(註釋|注釋|校勘|參考|参考|參見|参见)').hasMatch(line)) break;
    lines.add(line);
  }
  return lines;
}

/// 没有 poem/onlyinclude 时：去掉头部模板与分类，退回剩余正文。
String _stripHeaderTemplate(String wikitext) {
  var text = wikitext.replaceAll(RegExp(r'\{\{header[\s\S]*?\n\}\}'), '');
  text = text.replaceAll(RegExp(r'\[\[Category:[^\]]*\]\]'), '');
  text = text.replaceAll(RegExp(r'\{\{Vtext[^}]*\}\}'), '');
  return text;
}
