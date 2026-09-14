/// 公版书单 / 作品单：全部为公有领域或 CC 授权内容。
class WikisourceWork {
  const WikisourceWork(
    this.title,
    this.display,
    this.author, {
    this.classical = false,
  });

  /// 维基文库页面名（含子页）。
  final String title;

  /// 卡片标题展示名。
  final String display;

  /// 作者。
  final String author;

  /// 是否为文言/繁体经典（卡片署名会标注「文言」）。
  final bool classical;
}

class GutenbergWork {
  const GutenbergWork(this.id, this.title, this.author);

  final int id;
  final String title;
  final String author;
}

/// 古文经典（文言）：整篇成卡，署名标注「文言」。
const List<WikisourceWork> classicWorksZh = <WikisourceWork>[
  // 诸子
  WikisourceWork('莊子/逍遙遊', '逍遙遊', '莊子', classical: true),
  WikisourceWork('莊子/齊物論', '齊物論', '莊子', classical: true),
  WikisourceWork('莊子/養生主', '養生主', '莊子', classical: true),
  WikisourceWork('論語/學而第一', '學而第一', '論語', classical: true),
  WikisourceWork('論語/爲政第二', '爲政第二', '論語', classical: true),
  WikisourceWork('論語/里仁第四', '里仁第四', '論語', classical: true),
  WikisourceWork('孟子/梁惠王上', '梁惠王上', '孟子', classical: true),
  WikisourceWork('孟子/公孫丑上', '公孫丑上', '孟子', classical: true),
  WikisourceWork('荀子/勸學篇', '勸學篇', '荀子', classical: true),
  WikisourceWork('荀子/天論篇', '天論篇', '荀子', classical: true),
  WikisourceWork('禮記/大學', '大學', '禮記', classical: true),
  WikisourceWork('禮記/中庸', '中庸', '禮記', classical: true),
  WikisourceWork('墨子/兼愛上', '兼愛上', '墨子', classical: true),
  WikisourceWork('韓非子/難一', '難一', '韓非子', classical: true),
  // 詩詞賦
  WikisourceWork('詩經/關雎', '關雎', '詩經', classical: true),
  WikisourceWork('詩經/蒹葭', '蒹葭', '詩經', classical: true),
  WikisourceWork('離騷', '離騷', '屈原', classical: true),
  WikisourceWork('木蘭詩', '木蘭詩', '佚名', classical: true),
  WikisourceWork('洛神賦', '洛神賦', '曹植', classical: true),
  WikisourceWork('歸園田居', '歸園田居', '陶淵明', classical: true),
  WikisourceWork('桃花源記', '桃花源記', '陶淵明', classical: true),
  // 駢散文
  WikisourceWork('滕王閣序', '滕王閣序', '王勃', classical: true),
  WikisourceWork('春夜宴桃李園序', '春夜宴桃李園序', '李白', classical: true),
  WikisourceWork('師說', '師說', '韓愈', classical: true),
  WikisourceWork('陋室銘', '陋室銘', '劉禹錫', classical: true),
  WikisourceWork('阿房宮賦', '阿房宮賦', '杜牧', classical: true),
  WikisourceWork('愛蓮說', '愛蓮說', '周敦頤', classical: true),
  WikisourceWork('岳陽樓記', '岳陽樓記', '范仲淹', classical: true),
  WikisourceWork('醉翁亭記', '醉翁亭記', '歐陽修', classical: true),
  WikisourceWork('前赤壁賦', '前赤壁賦', '蘇軾', classical: true),
  WikisourceWork('後赤壁賦', '後赤壁賦', '蘇軾', classical: true),
  WikisourceWork('諫太宗十思疏', '諫太宗十思疏', '魏徵', classical: true),
  WikisourceWork('出師表', '出師表', '諸葛亮', classical: true),
  WikisourceWork('蘭亭集序', '蘭亭集序', '王羲之', classical: true),
  WikisourceWork('與朱元思書', '與朱元思書', '吳均', classical: true),
  WikisourceWork('誡子書', '誡子書', '諸葛亮', classical: true),
  WikisourceWork('世說新語/德行', '德行', '世說新語', classical: true),
];

/// 短篇小说 / 散文（白话，公有领域）。
const List<WikisourceWork> proseWorksZh = <WikisourceWork>[
  // 魯迅
  WikisourceWork('狂人日記', '狂人日記', '魯迅'),
  WikisourceWork('孔乙己', '孔乙己', '魯迅'),
  WikisourceWork('藥', '藥', '魯迅'),
  WikisourceWork('故鄉', '故鄉', '魯迅'),
  WikisourceWork('社戲', '社戲', '魯迅'),
  WikisourceWork('阿Q正傳', '阿Q正傳', '魯迅'),
  WikisourceWork('祝福', '祝福', '魯迅'),
  WikisourceWork('一件小事', '一件小事', '魯迅'),
  WikisourceWork('風波', '風波', '魯迅'),
  WikisourceWork('明天', '明天', '魯迅'),
  WikisourceWork('白光', '白光', '魯迅'),
  WikisourceWork('頭髮的故事', '頭髮的故事', '魯迅'),
  WikisourceWork('從百草園到三味書屋', '從百草園到三味書屋', '魯迅'),
  // 朱自清
  WikisourceWork('背影', '背影', '朱自清'),
  WikisourceWork('荷塘月色', '荷塘月色', '朱自清'),
  WikisourceWork('匆匆', '匆匆', '朱自清'),
  WikisourceWork('槳聲燈影裏的秦淮河', '槳聲燈影裏的秦淮河', '朱自清'),
  // 其他白话作者
  WikisourceWork('差不多先生傳', '差不多先生傳', '胡適'),
  WikisourceWork('春風沉醉的晚上', '春風沉醉的晚上', '郁達夫'),
  WikisourceWork('釣臺的春晝', '釣臺的春晝', '郁達夫'),
  WikisourceWork('落花生', '落花生', '許地山'),
  WikisourceWork('我的母親', '我的母親', '胡適'),
  WikisourceWork('回憶魯迅先生', '回憶魯迅先生', '蕭紅'),
  WikisourceWork('我所知道的康橋', '我所知道的康橋', '徐志摩'),
];

/// 英文经典书籍（古登堡计划）。英文占比开启时使用，按章取整章。
const List<GutenbergWork> classicWorksEn = <GutenbergWork>[
  GutenbergWork(2680, 'Meditations', 'Marcus Aurelius'),
  GutenbergWork(1497, 'The Republic', 'Plato'),
  GutenbergWork(4363, 'Beyond Good and Evil', 'Friedrich Nietzsche'),
  GutenbergWork(1998, 'Thus Spoke Zarathustra', 'Friedrich Nietzsche'),
  GutenbergWork(8438, 'Nicomachean Ethics', 'Aristotle'),
  GutenbergWork(216, 'The Tao Teh King', 'Laozi'),
  GutenbergWork(3330, 'The Analects of Confucius', 'Confucius'),
  GutenbergWork(132, 'The Art of War', 'Sun Tzu'),
  GutenbergWork(5827, 'The Problems of Philosophy', 'Bertrand Russell'),
  GutenbergWork(9662, 'An Enquiry Concerning Human Understanding', 'David Hume'),
  GutenbergWork(1232, 'The Prince', 'Niccolò Machiavelli'),
  GutenbergWork(2130, 'Utopia', 'Thomas More'),
  GutenbergWork(3207, 'Leviathan', 'Thomas Hobbes'),
  GutenbergWork(1974, 'Poetics', 'Aristotle'),
];

/// 英文短篇小说作者检索词（古登堡计划在线检索）。
const List<String> proseAuthorsEn = <String>[
  'Anton Chekhov',
  'Edgar Allan Poe',
  'Guy de Maupassant',
  'O. Henry',
  'Katherine Mansfield',
  'Joseph Conrad',
];

/// 实用技能：维基教科书检索词（wikiHow 不可达时的备用源）。
/// 偏向「能跟着做」的主题，避免抽到教科书式的理论章节。
const List<String> howToQueriesZh = <String>[
  // 以 `/` 结尾的条目走标题前缀检索（如「食谱/」下的菜谱子页）。
  '食谱/',
  '食譜/',
  '食谱/家常菜',
  '食谱/汤',
  '食谱/甜点',
  '烘焙',
  '烹饪',
  '急救',
  '手工',
  '编织',
  '园艺',
  '摄影',
  '收纳',
  '健身',
  '清洁',
  '旅行',
];

/// 中文维基教科书里「能跟着做」的实用主题根名（用于过滤教科书式的理论章节）。
/// 只有根名命中这里，条目才会被当作实用技能卡。
const List<String> practicalBookRoots = <String>[
  '食谱',
  '食譜',
  '菜谱',
  '菜譜',
  '家常菜',
  '烹饪',
  '烹飪',
  '烘焙',
  '甜点',
  '甜點',
  '素食',
  '饮料',
  '飲料',
  '急救',
  '手工',
  '编织',
  '編織',
  '园艺',
  '園藝',
  '花艺',
  '花藝',
  '摄影',
  '攝影',
  '收纳',
  '收納',
  '清洁',
  '清潔',
  '家居',
  '旅行',
  '健身',
  '瑜伽',
  '瑜珈',
  '游泳',
  '钓鱼',
  '釣魚',
  '魔术',
  '魔術',
];
