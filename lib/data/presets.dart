/// 公版书单 / 作品单：全部为公有领域或 CC 授权内容。
class WikisourceWork {
  const WikisourceWork(this.title, this.display, this.author);

  /// 维基文库页面名（含子页）。
  final String title;

  /// 卡片标题展示名。
  final String display;

  /// 作者。
  final String author;
}

class GutenbergWork {
  const GutenbergWork(this.id, this.title, this.author);

  final int id;
  final String title;
  final String author;
}

/// 哲学 / 经典书籍选段（中文部分）。
const List<WikisourceWork> classicWorksZh = <WikisourceWork>[
  WikisourceWork('莊子/逍遙遊', '逍遙遊', '莊子'),
  WikisourceWork('論語/學而第一', '學而第一', '論語'),
  WikisourceWork('論語/爲政第二', '爲政第二', '論語'),
  WikisourceWork('孟子/梁惠王上', '梁惠王上', '孟子'),
  WikisourceWork('荀子/勸學篇', '勸學篇', '荀子'),
  WikisourceWork('詩經/關雎', '關雎', '詩經'),
  WikisourceWork('世說新語/德行', '德行', '世說新語'),
  WikisourceWork('離騷', '離騷', '屈原'),
  WikisourceWork('桃花源記', '桃花源記', '陶淵明'),
  WikisourceWork('歸去來兮辭', '歸去來兮辭', '陶淵明'),
  WikisourceWork('岳陽樓記', '岳陽樓記', '范仲淹'),
  WikisourceWork('蘭亭集序', '蘭亭集序', '王羲之'),
  WikisourceWork('醉翁亭記', '醉翁亭記', '歐陽修'),
  WikisourceWork('前赤壁賦', '前赤壁賦', '蘇軾'),
  WikisourceWork('出師表', '出師表', '諸葛亮'),
  WikisourceWork('陳情表', '陳情表', '李密'),
  WikisourceWork('滕王閣序', '滕王閣序', '王勃'),
  WikisourceWork('陋室銘', '陋室銘', '劉禹錫'),
  WikisourceWork('愛蓮說', '愛蓮說', '周敦頤'),
  WikisourceWork('師說', '師說', '韓愈'),
  WikisourceWork('阿房宮賦', '阿房宮賦', '杜牧'),
  WikisourceWork('六國論', '六國論', '蘇洵'),
  WikisourceWork('諫太宗十思疏', '諫太宗十思疏', '魏徵'),
];

/// 短篇小说 / 散文（中文部分）。
const List<WikisourceWork> proseWorksZh = <WikisourceWork>[
  WikisourceWork('狂人日記', '狂人日記', '魯迅'),
  WikisourceWork('孔乙己', '孔乙己', '魯迅'),
  WikisourceWork('藥', '藥', '魯迅'),
  WikisourceWork('故鄉', '故鄉', '魯迅'),
  WikisourceWork('社戲', '社戲', '魯迅'),
  WikisourceWork('阿Q正傳', '阿Q正傳', '魯迅'),
  WikisourceWork('祝福', '祝福', '魯迅'),
  WikisourceWork('從百草園到三味書屋', '從百草園到三味書屋', '魯迅'),
  WikisourceWork('背影', '背影', '朱自清'),
  WikisourceWork('荷塘月色', '荷塘月色', '朱自清'),
  WikisourceWork('匆匆', '匆匆', '朱自清'),
  WikisourceWork('槳聲燈影裏的秦淮河', '槳聲燈影裏的秦淮河', '朱自清'),
  WikisourceWork('差不多先生傳', '差不多先生傳', '胡適'),
];

/// 英文经典书籍（古登堡计划）。网络受限或编号失效时自动退回按书名搜索。
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
  '食谱/家常菜',
  '食谱/汤',
  '食谱/甜点',
  '烹饪',
  '烘焙',
  '急救',
  '摄影',
  '收纳',
  '园艺',
  '健身',
  '手工',
  '编织',
  '旅行',
  '清洁',
];
