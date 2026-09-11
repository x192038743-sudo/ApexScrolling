import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/feed_repository.dart';
import '../data/net_client.dart';
import '../models/text_card.dart';
import 'providers.dart';

/// 信息流状态。
class FeedState {
  const FeedState({
    this.cards = const <TextCard>[],
    this.loading = false,
    this.offline = false,
    this.message,
  });

  final List<TextCard> cards;
  final bool loading;

  /// 正在阅读离线缓存卡片。
  final bool offline;

  /// 顶部提示文案（无网、源不可用等）。
  final String? message;

  bool get isEmpty => cards.isEmpty;

  FeedState copyWith({
    List<TextCard>? cards,
    bool? loading,
    bool? offline,
    String? message,
    bool clearMessage = false,
  }) =>
      FeedState(
        cards: cards ?? this.cards,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// 滑动信息流控制器：预取、去重、换源重抽、兔子洞插入。
class FeedController extends Notifier<FeedState> {
  static const int prefetchAhead = 3;

  final Set<String> _seenIds = <String>{};
  int _inFlight = 0;

  FeedRepository get _repository => ref.read(feedRepositoryProvider);

  @override
  FeedState build() => const FeedState();

  /// 保证 index 之后至少有 [ahead] 张卡片。
  Future<void> ensurePrefetch(
    int index, {
    int ahead = prefetchAhead,
    int maxLoads = 3,
  }) async {
    final List<Future<bool>> pending = <Future<bool>>[];
    while (state.cards.length + pending.length <= index + ahead &&
        pending.length < maxLoads) {
      pending.add(loadMore());
    }
    if (pending.isEmpty) return;
    await Future.wait(pending);
  }

  /// 抓取一张新卡片并追加到信息流末尾。
  Future<bool> loadMore() async {
    if (_inFlight >= 3) return false;
    _inFlight++;
    state = state.copyWith(loading: true, clearMessage: true);
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final FeedFetchResult result = await _repository.nextCard();
        if (_seenIds.add(result.card.id)) {
          state = state.copyWith(
            cards: <TextCard>[...state.cards, result.card],
            loading: false,
            offline: result.fromCache,
            message: result.fromCache ? '网络不可用 · 正在浏览缓存卡片' : null,
            clearMessage: !result.fromCache,
          );
          return true;
        }
      }
      state = state.copyWith(loading: false);
      return false;
    } on SourceException catch (error) {
      state = state.copyWith(
        loading: false,
        offline: true,
        message: '内容源暂时不可用 · ${error.message}',
      );
      return false;
    } finally {
      _inFlight--;
    }
  }

  /// 词条内链 → 在当前位置插入新卡（兔子洞，深度上限 5）。
  Future<TextCard?> openLink(int index, CardLink link) async {
    if (index < 0 || index >= state.cards.length) return null;
    final TextCard parent = state.cards[index];
    try {
      final TextCard card = await _repository.digDeeper(parent, link);
      if (!_seenIds.add(card.id)) return null;
      final List<TextCard> cards = List<TextCard>.of(state.cards)
        ..insert(index + 1, card);
      state = state.copyWith(
        cards: cards,
        offline: false,
        clearMessage: true,
      );
      return card;
    } on SourceException catch (error) {
      state = state.copyWith(message: '内链打开失败 · ${error.message}');
      return null;
    }
  }

  void clearMessage() {
    if (state.message == null) return;
    state = state.copyWith(clearMessage: true);
  }
}
