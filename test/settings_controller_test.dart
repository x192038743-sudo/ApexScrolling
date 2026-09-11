import 'dart:convert';

import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/state/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
  });

  test('默认六源全开、字号标准、跟随系统、宽松冷门度', () {
    final AppSettings settings = container.read(settingsControllerProvider);
    expect(settings.enabledSources, hasLength(6));
    expect(settings.fontScaleLevel, 1);
    expect(settings.theme, AppThemeOption.system);
    expect(settings.wikiRarity, WikiRarity.loose);
    expect(settings.fontScale, 1.0);
  });

  test('逐源开关会持久化，且至少保留一个源', () {
    final SettingsController controller =
        container.read(settingsControllerProvider.notifier);
    controller.toggleSource(CardKind.poetry);
    expect(
      container.read(settingsControllerProvider).isEnabled(CardKind.poetry),
      isFalse,
    );

    final Map<String, dynamic> stored = jsonDecode(
      prefs.getString(SettingsController.storageKey)!,
    ) as Map<String, dynamic>;
    expect(stored['enabledSources'], isNot(contains('poetry')));

    // 关到只剩一个后不再允许继续关闭。
    for (final CardKind kind in <CardKind>[
      CardKind.wikiTerm,
      CardKind.philosophy,
      CardKind.classicExcerpt,
      CardKind.prose,
      CardKind.howTo,
    ]) {
      controller.toggleSource(kind);
    }
    expect(container.read(settingsControllerProvider).enabledSources, hasLength(1));
  });

  test('字号三档与冷门度、主题可切换', () {
    final SettingsController controller =
        container.read(settingsControllerProvider.notifier);
    controller.setFontScaleLevel(2);
    controller.setTheme(AppThemeOption.dark);
    controller.setWikiRarity(WikiRarity.strict);

    final AppSettings settings = container.read(settingsControllerProvider);
    expect(settings.fontScale, AppSettings.fontScales[2]);
    expect(settings.theme, AppThemeOption.dark);
    expect(settings.wikiRarity.maxSitelinks, 20);
  });

  test('重新读取时从本地恢复设置', () {
    final SettingsController controller =
        container.read(settingsControllerProvider.notifier);
    controller.setFontScaleLevel(0);

    final ProviderContainer restored = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(restored.dispose);
    expect(restored.read(settingsControllerProvider).fontScaleLevel, 0);
  });
}
