import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/text_card.dart';

/// 卡片本地缓存：无网时继续有内容可读（不含任何用户数据）。
class CardCache {
  CardCache(this._prefs, {Random? random}) : _rng = random ?? Random();

  static const String _key = 'apex.card_cache.v1';

  /// 缓存上限：够离线刷一段，又不至于让设置文件过大。
  static const int maxEntries = 60;

  final SharedPreferences _prefs;
  final Random _rng;

  List<TextCard> load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <TextCard>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <TextCard>[];
      return decoded
          .whereType<String>()
          .map((String item) {
            try {
              return TextCard.decode(item);
            } catch (_) {
              return null;
            }
          })
          .whereType<TextCard>()
          .toList();
    } catch (_) {
      return <TextCard>[];
    }
  }

  /// 只缓存「原生卡片」，兔子洞卡片不落盘。
  Future<void> save(TextCard card) async {
    if (card.depth > 0) return;
    final List<TextCard> cards = load();
    cards.removeWhere((TextCard item) => item.id == card.id);
    cards.insert(0, card);
    final List<String> trimmed = cards
        .take(maxEntries)
        .map((TextCard item) => item.encode())
        .toList(growable: false);
    await _prefs.setString(_key, jsonEncode(trimmed));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }

  /// 离线时随机取一张缓存卡片（优先取较新的）。
  TextCard? randomCard() {
    final List<TextCard> cards = load();
    if (cards.isEmpty) return null;
    final int window = min(cards.length, 20);
    return cards[_rng.nextInt(window)];
  }
}
