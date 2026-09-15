import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/text_card.dart';
import 'providers.dart';

/// 本地设置读写（SharedPreferences，无账号无云端）。
class SettingsController extends Notifier<AppSettings> {
  static const String storageKey = 'apex.settings.v1';

  late final SharedPreferences _prefs;

  @override
  AppSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final String? raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  void toggleSource(CardKind kind) {
    final Set<CardKind> sources = Set<CardKind>.of(state.enabledSources);
    if (sources.contains(kind)) {
      if (sources.length == 1) return; // 至少保留一个源
      sources.remove(kind);
    } else {
      sources.add(kind);
    }
    _update(state.copyWith(enabledSources: sources));
  }

  void setFontScaleLevel(int level) =>
      _update(state.copyWith(fontScaleLevel: level.clamp(0, 2)));

  void setTheme(AppThemeOption theme) => _update(state.copyWith(theme: theme));

  void setWikiRarity(WikiRarity rarity) =>
      _update(state.copyWith(wikiRarity: rarity));

  /// 英文内容占比（0–100，按 10% 一档保存）。
  void setEnglishPercent(int percent) {
    final int clamped = percent.clamp(0, 100);
    final int snapped = (clamped / 10).round() * 10;
    _update(state.copyWith(englishPercent: snapped));
  }

  void _update(AppSettings next) {
    state = next;
    _prefs.setString(storageKey, jsonEncode(next.toJson()));
  }
}
