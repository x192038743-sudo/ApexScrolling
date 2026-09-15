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
  }) : _net = net,
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

  /// 待轮换的内容源。不能只按接口响应速度抢卡，否则响应很快的诗词接口
  /// 会把维基百科、古登堡等较慢但重要的内容源长期压住。
  final List<CardKind> _sourceQueue = <CardKind>[];

  /// 本次运行已经展示过的卡片 ID，避免接口或离线缓存重复返回同一张卡。
  final List<String> _recentCardIds = <String>[];
  static const int _recentCardWindow = 240;

  int _settingsGeneration = 0;

  AppSettings _settings;

  AppSettings get settings => _settings;

  /// 设置变化：重新构建受影响的适配器（词条阈值/开关）。
  void updateSettings(AppSettings settings) {
    final bool rarityChanged = settings.wikiRarity != _settings.wikiRarity;
    final bool languageChanged =
        settings.englishPercent != _settings.englishPercent;
    final bool sourcesChanged = !_sameSet(
      settings.enabledSources,
      _settings.enabledSources,
    );
    _settings = settings;
    if (languageChanged || sourcesChanged || rarityChanged) {
      _settingsGeneration++;
      _sourceQueue.clear();
    }
    if (!rarityChanged) return;
    final CardAdapter? existing = _adapters[CardKind.wikiTerm];
    if (existing is WikiTermAdapter || existing == null) {
      _adapters[CardKind.wikiTerm] = WikiTermAdapter(
        _net,
        settings,
        random: _rng,
      );
    }
  }

  SourceHealth healthOf(CardKind kind) =>
      _health.putIfAbsent(kind, SourceHealth.new);

  /// 本次出卡是否走英文提供者：按设置的英文占比掷骰子。
  bool _shouldUseEnglish() {
    final int percent = _settings.englishPercent.clamp(0, 100);
    if (percent <= 0) return false;
    if (percent >= 100) return true;
    return _rng.nextInt(100) < percent;
  }

  /// 取下一张卡片。
  ///
  /// 策略：按轮换队列公平选择内容源，失败再换源；不再让响应最快的
  /// 接口（通常是诗词）长期垄断信息流。全部失败则回落离线缓存。
  Future<FeedFetchResult> nextCard({int attempts = 2}) async {
    final List<CardKind> enabled = _settings.enabledSources.toList();
    if (enabled.isEmpty) {
      throw SourceException('已关闭全部内容源');
    }
    final List<CardKind> available = enabled
        .where((CardKind kind) => !healthOf(kind).isBlocked)
        .toList();
    // 全部熔断时也允许兜底试一次，避免长时间无内容。
    final List<CardKind> pool = available.isEmpty ? enabled : available;
    final int generation = _settingsGeneration;
    final List<String> errors = <String>[];
    final int sourceAttempts = max(1, min(attempts, pool.length));
    for (var sourceTry = 0; sourceTry < sourceAttempts; sourceTry++) {
      final List<CardKind> next = _takeSources(pool, 1);
      if (next.isEmpty) break;
      final CardKind kind = next.first;
      if (_adapters[kind] == null) continue;
      try {
        final TextCard card = await _fetchFrom(kind);
        // 设置在请求期间改变时，丢弃旧语言/旧源结果，避免旧请求回流。
        if (generation != _settingsGeneration ||
            !_settings.enabledSources.contains(card.kind)) {
          continue;
        }
        if (_recentCardIds.contains(card.id)) {
          errors.add('${kind.label}: 重复卡片');
          continue;
        }
        _rememberCard(card.id);
        return FeedFetchResult(card: card, fromCache: false, errors: errors);
      } on SourceException catch (error) {
        errors.add(error.message);
      }
    }

    // 所有候选源失败：退回离线缓存，只取当前启用且未展示过的卡片。
    final TextCard? cached = _cache.randomCard(
      where: (TextCard card) =>
          _settings.enabledSources.contains(card.kind) &&
          !_recentCardIds.contains(card.id) &&
          (_settings.englishPercent != 0 || !card.isEnglish),
    );
    if (cached != null) {
      _rememberCard(cached.id);
      return FeedFetchResult(card: cached, fromCache: true, errors: errors);
    }
    throw SourceException(errors.isEmpty ? '网络不可用' : errors.first);
  }

  /// 从轮换队列取出本次要尝试的源；每轮会覆盖所有启用源一次。
  List<CardKind> _takeSources(List<CardKind> pool, int count) {
    final Set<CardKind> allowed = pool.toSet();
    _sourceQueue.removeWhere((CardKind kind) => !allowed.contains(kind));
    while (_sourceQueue.length < count) {
      final List<CardKind> refill = allowed
          .where((CardKind kind) => !_sourceQueue.contains(kind))
          .toList();
      if (refill.isEmpty) break;
      refill.shuffle(_rng);
      _sourceQueue.addAll(refill);
    }
    final int take = min(count, _sourceQueue.length);
    final List<CardKind> selected = _sourceQueue.sublist(0, take);
    _sourceQueue.removeRange(0, take);
    return selected;
  }

  void _rememberCard(String id) {
    _recentCardIds
      ..remove(id)
      ..add(id);
    while (_recentCardIds.length > _recentCardWindow) {
      _recentCardIds.removeAt(0);
    }
  }

  static bool _sameSet(Set<CardKind> a, Set<CardKind> b) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }

  Future<TextCard> _fetchFrom(CardKind kind) async {
    final CardAdapter adapter = _adapters[kind]!;
    try {
      final TextCard card = await adapter.fetch(
        preferEnglish: _shouldUseEnglish(),
      );
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
