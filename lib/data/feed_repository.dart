import 'dart:async';
import 'dart:math';

import '../core/endpoints.dart';
import '../models/app_settings.dart';
import '../models/text_card.dart';
import 'adapters/card_adapter.dart';
import 'adapters/classic_excerpt_adapter.dart';
import 'adapters/howto_adapter.dart';
import 'adapters/philosophy_adapter.dart';
import 'adapters/poetry_adapter.dart';
import 'adapters/prose_adapter.dart';
import 'adapters/wiki_term_adapter.dart';
import 'card_cache.dart';
import 'net_client.dart';

/// 单个数据源的健康状况（连续失败 → 熔断 60s）。
class SourceHealth {
  int consecutiveFailures = 0;
  DateTime? blockedUntil;

  bool get isBlocked =>
      blockedUntil != null && DateTime.now().isBefore(blockedUntil!);

  void recordSuccess() {
    consecutiveFailures = 0;
    blockedUntil = null;
  }

  void recordFailure() {
    consecutiveFailures++;
    if (consecutiveFailures >= NetPolicy.circuitBreakerThreshold) {
      blockedUntil = DateTime.now().add(NetPolicy.circuitBreakerCooldown);
      consecutiveFailures = 0;
    }
  }
}

/// 抓取结果：来源是否全部熔断、是否走了离线缓存。
class FeedFetchResult {
  const FeedFetchResult({
    required this.card,
    required this.fromCache,
    this.errors = const <String>[],
  });

  final TextCard card;
  final bool fromCache;
  final List<String> errors;
}

/// 信息流数据仓库：六源等权随机抽源、失败换源、熔断、离线兜底。
class FeedRepository {
  FeedRepository({
    required NetClient net,
    required CardCache cache,
    Random? random,
    AppSettings settings = const AppSettings(),
    Map<CardKind, CardAdapter>? adapters,
  })  : _net = net,
        _cache = cache,
        _rng = random ?? Random(),
        _settings = settings {
    _adapters = <CardKind, CardAdapter>{
      CardKind.wikiTerm: WikiTermAdapter(_net, settings, random: _rng),
      CardKind.philosophy: PhilosophyAdapter(_net, random: _rng),
      CardKind.classicExcerpt: ClassicExcerptAdapter(_net, random: _rng),
      CardKind.prose: ProseAdapter(_net, random: _rng),
      CardKind.howTo: HowToAdapter(_net, random: _rng),
      CardKind.poetry: PoetryAdapter(_net),
      ...?adapters,
    };
  }

  final NetClient _net;
  final CardCache _cache;
  final Random _rng;
  late final Map<CardKind, CardAdapter> _adapters;
  final Map<CardKind, SourceHealth> _health = <CardKind, SourceHealth>{};
  final List<TextCard> _ready = <TextCard>[];

  AppSettings _settings;

  AppSettings get settings => _settings;

  /// 设置变化：重新构建受影响的适配器（词条阈值/开关）。
  void updateSettings(AppSettings settings) {
    final bool rarityChanged = settings.wikiRarity != _settings.wikiRarity;
    _settings = settings;
    if (!rarityChanged) return;
    final CardAdapter? existing = _adapters[CardKind.wikiTerm];
    if (existing is WikiTermAdapter || existing == null) {
      _adapters[CardKind.wikiTerm] =
          WikiTermAdapter(_net, settings, random: _rng);
    }
  }

  SourceHealth healthOf(CardKind kind) =>
      _health.putIfAbsent(kind, SourceHealth.new);

  /// 取下一张卡片。
  ///
  /// 策略：并发竞速抓取 2 个源，先成功者立即出卡，
  /// 后成功的结果进入就绪队列（下一次秒出），全部失败则回落离线缓存。
  Future<FeedFetchResult> nextCard({int attempts = 2}) async {
    if (_ready.isNotEmpty) {
      return FeedFetchResult(card: _ready.removeAt(0), fromCache: false);
    }
    final List<CardKind> enabled = _settings.enabledSources.toList();
    if (enabled.isEmpty) {
      throw SourceException('已关闭全部内容源');
    }
    final List<CardKind> available = enabled
        .where((CardKind kind) => !healthOf(kind).isBlocked)
        .toList();
    // 全部熔断时也允许兜底试一次，避免长时间无内容。
    final List<CardKind> pool =
        available.isEmpty ? enabled : available;
    pool.shuffle(_rng);

    final List<String> errors = <String>[];
    final List<Future<TextCard>> racing = <Future<TextCard>>[
      for (final CardKind kind in pool.take(attempts))
        if (_adapters[kind] != null) _fetchFrom(kind),
    ];
    final TextCard? card = racing.isEmpty
        ? null
        : await _race(racing, errors);
    if (card != null) {
      return FeedFetchResult(card: card, fromCache: false, errors: errors);
    }

    // 三源皆失败：退回离线缓存。
    final TextCard? cached = _cache.randomCard();
    if (cached != null) {
      return FeedFetchResult(card: cached, fromCache: true, errors: errors);
    }
    throw SourceException(
      errors.isEmpty ? '网络不可用' : errors.first,
    );
  }

  /// 竞速：首个成功的卡片优先返回，其余成功结果暂存待用。
  Future<TextCard?> _race(
    List<Future<TextCard>> futures,
    List<String> errors,
  ) async {
    final Completer<TextCard?> completer = Completer<TextCard?>();
    var pending = futures.length;
    for (final Future<TextCard> future in futures) {
      future.then(
        (TextCard card) {
          if (completer.isCompleted) {
            _stash(card);
          } else {
            completer.complete(card);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          errors.add('$error');
          pending--;
          if (pending == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
    }
    return completer.future;
  }

  /// 预取结果暂存（最多 3 张，避免无界增长）。
  void _stash(TextCard card) {
    if (_ready.length >= 3) return;
    if (_ready.any((TextCard item) => item.id == card.id)) return;
    _ready.add(card);
  }

  Future<TextCard> _fetchFrom(CardKind kind) async {
    final CardAdapter adapter = _adapters[kind]!;
    try {
      final TextCard card = await adapter.fetch();
      healthOf(kind).recordSuccess();
      await _cache.save(card);
      return card;
    } catch (error) {
      healthOf(kind).recordFailure();
      if (error is SourceException) {
        throw SourceException('${adapter.displayName}: ${error.message}');
      }
      throw SourceException('${adapter.displayName}: $error');
    }
  }

  /// 兔子洞：按内链抓取一张更深一层的词条卡。
  Future<TextCard> digDeeper(TextCard parent, CardLink link) async {
    if (!parent.canDigDeeper) {
      throw SourceException('已达兔子洞最大深度');
    }
    final WikiTermAdapter? adapter =
        _adapters[CardKind.wikiTerm] as WikiTermAdapter?;
    if (adapter == null) {
      throw SourceException('词条源不可用');
    }
    final TextCard card = await adapter.fetchByTitle(
      link.title,
      lang: link.lang,
      depth: parent.depth + 1,
    );
    await _cache.save(card);
    return card;
  }

  /// 预置缓存（首次启动无网时直接可用）。
  Future<void> warmUpCache() async {
    if (_cache.load().isNotEmpty) return;
    try {
      final FeedFetchResult result = await nextCard(attempts: 1);
      if (!result.fromCache) return;
    } on SourceException {
      // 无网且无缓存：留给 UI 提示。
    }
  }
}
