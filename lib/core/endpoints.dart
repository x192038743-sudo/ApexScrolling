/// 全局网络常量：所有数据源地址集中在此，便于替换镜像或做灰度。
class Endpoints {
  const Endpoints._();

  /// 规范 User-Agent：Wikimedia 系列接口要求可识别的 UA。
  ///
  /// 注意：HTTP 头只允许 ASCII（Latin-1），这里不能出现中文，
  /// 否则底层会抛 `Invalid HTTP header field value`。
  static const String userAgent =
      'ApexScrolling/1.0 (Flutter; text-only reading feed; +https://example.org/apexscrolling)';

  // ---------------------------------------------------------------- Wikipedia
  /// Wikimedia 官方 REST（api.wikimedia.org）。
  ///
  /// 之所以不用 `zh.wikipedia.org/api/rest_v1`：部分网络环境下
  /// `*.wikipedia.org` 不可达，而 `api.wikimedia.org` 稳定可用，
  /// 且同样返回经渲染的条目 HTML。
  static const String wikipediaApiBase =
      'https://api.wikimedia.org/core/v1/wikipedia';

  /// Wikidata 查询服务（SPARQL），用于筛选「冷门学术词条」。
  static const String wikidataSparql = 'https://query.wikidata.org/sparql';

  // -------------------------------------------------------------- Wikisource
  /// 中文维基文库 Action API（公版书籍 / 小说 / 散文）。
  static const String wikisourceApi = 'https://zh.wikisource.org/w/api.php';

  /// 中文维基教科书 Action API（实用技能源的备用源）。
  static const String wikibooksApi = 'https://zh.wikibooks.org/w/api.php';

  // --------------------------------------------------------------- Gutendex
  /// 古登堡计划镜像 API（英文公版书全文）。
  static const String gutendexApi = 'https://gutendex.com/books';

  // ----------------------------------------------------------- Philosophy
  /// 斯坦福哲学百科（SEP）无公开 API，直接解析条目 HTML。
  static const String sepBase = 'https://plato.stanford.edu';
  static const String sepContents = '$sepBase/contents.html';

  // --------------------------------------------------------------- wikiHow
  static const String wikihowZhApi = 'https://zh.wikihow.com/api.php';
  static const String wikihowEnApi = 'https://www.wikihow.com/api.php';

  // ------------------------------------------------------------- 今日诗词
  static const String jinrishiciApi = 'https://v1.jinrishici.com/all.json';
}

/// 网络超时与重试策略。
class NetPolicy {
  const NetPolicy._();

  /// 单次请求超时（Wikidata SPARQL 较慢，单独放宽）。
  static const Duration requestTimeout = Duration(seconds: 20);
  static const Duration sparqlTimeout = Duration(seconds: 45);
  static const Duration downloadTimeout = Duration(seconds: 30);

  /// 单个适配器的内部重试次数（换一篇/换一条再试）。
  static const int adapterAttempts = 3;

  /// 同一数据源连续失败多少次后熔断。
  static const int circuitBreakerThreshold = 2;

  /// 熔断持续时间。
  static const Duration circuitBreakerCooldown = Duration(seconds: 60);
}
