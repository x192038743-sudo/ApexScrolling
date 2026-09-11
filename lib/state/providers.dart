import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/card_cache.dart';
import '../data/feed_repository.dart';
import '../data/net_client.dart';
import '../models/app_settings.dart';
import 'feed_controller.dart';
import 'settings_controller.dart';

/// `main()` 中用真实实例覆盖。
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError('sharedPreferencesProvider 未初始化'),
);

/// 全局 HTTP 客户端（可注入假实现用于测试）。
final Provider<NetClient> netClientProvider = Provider<NetClient>((Ref ref) {
  final NetClient client = NetClient();
  ref.onDispose(client.close);
  return client;
});

final Provider<CardCache> cardCacheProvider = Provider<CardCache>(
  (Ref ref) => CardCache(ref.watch(sharedPreferencesProvider)),
);

final NotifierProvider<SettingsController, AppSettings>
    settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final Provider<FeedRepository> feedRepositoryProvider =
    Provider<FeedRepository>((Ref ref) {
  final FeedRepository repository = FeedRepository(
    net: ref.watch(netClientProvider),
    cache: ref.watch(cardCacheProvider),
    settings: ref.watch(settingsControllerProvider),
  );
  // 设置（源开关 / 冷门阈值）变化后同步到仓库。
  ref.listen<AppSettings>(settingsControllerProvider,
      (AppSettings? previous, AppSettings next) {
    repository.updateSettings(next);
  });
  return repository;
});

final NotifierProvider<FeedController, FeedState> feedControllerProvider =
    NotifierProvider<FeedController, FeedState>(FeedController.new);
