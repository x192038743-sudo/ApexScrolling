import 'dart:math';

import 'package:apex_scrolling/data/adapters/card_adapter.dart';
import 'package:apex_scrolling/data/card_cache.dart';
import 'package:apex_scrolling/data/feed_repository.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_utils.dart';

/// 总是失败的假适配器。
class _FailingAdapter implements CardAdapter {
  _FailingAdapter(this.kind, this.displayName);

  @override
  final CardKind kind;

  @override
  final String displayName;

  int calls = 0;

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    calls++;
    throw SourceException('模拟失败');
  }
}

/// 总是成功的假适配器。
class _OkAdapter implements CardAdapter {
  _OkAdapter(this.kind, this.displayName);

  @override
  final CardKind kind;

  @override
  final String displayName;

  int calls = 0;
  bool? lastPreferEnglish;

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    calls++;
    lastPreferEnglish = preferEnglish;
    return TextCard(
      id: '${kind.id}:$calls',
      kind: kind,
      title: '卡片 $calls',
      body: '正文内容' * 60,
      attribution: '测试源',
      fetchedAt: DateTime.now(),
    );
  }
}

Future<CardCache> buildCache([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return CardCache(prefs, random: Random(1));
}

FeedRepository buildRepository({
  required CardCache cache,
  required AppSettings settings,
  required Map<CardKind, CardAdapter> adapters,
}) => FeedRepository(
  net: NetClient(
    client: MockClient((http.Request request) async => emptyResponse()),
  ),
  cache: cache,
  settings: settings,
  adapters: adapters,
  random: Random(11),
);

void main() {
  test('单源失败自动换源重抽', () async {
    final _FailingAdapter failing = _FailingAdapter(CardKind.poetry, '诗词名句');
    final _OkAdapter ok = _OkAdapter(CardKind.howTo, '实用技能');
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(
        enabledSources: <CardKind>{CardKind.poetry, CardKind.howTo},
      ),
      adapters: <CardKind, CardAdapter>{
        CardKind.poetry: failing,
        CardKind.howTo: ok,
      },
    );

    final FeedFetchResult result = await repository.nextCard();
    expect(result.card.kind, CardKind.howTo);
    expect(result.fromCache, isFalse);
    expect(failing.calls + ok.calls, greaterThan(0));
  });

  test('同一源连续失败两次后熔断 60s', () async {
    final _FailingAdapter failing = _FailingAdapter(CardKind.poetry, '诗词名句');
    final _OkAdapter ok = _OkAdapter(CardKind.howTo, '实用技能');
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(enabledSources: <CardKind>{CardKind.poetry}),
      adapters: <CardKind, CardAdapter>{
        CardKind.poetry: failing,
        CardKind.howTo: ok,
      },
    );

    await expectLater(repository.nextCard(), throwsA(isA<SourceException>()));
    await expectLater(repository.nextCard(), throwsA(isA<SourceException>()));
    expect(repository.healthOf(CardKind.poetry).isBlocked, isTrue);

    // 打开另一个源后，熔断的源不再被调用。
    repository.updateSettings(
      const AppSettings(
        enabledSources: <CardKind>{CardKind.poetry, CardKind.howTo},
      ),
    );
    final FeedFetchResult result = await repository.nextCard();
    expect(result.card.kind, CardKind.howTo);
    expect(failing.calls, 2);
  });

  test('所有源失败时回落到本地缓存卡片', () async {
    final CardCache cache = await buildCache();
    await cache.save(
      TextCard(
        id: 'cached:1',
        kind: CardKind.poetry,
        title: '缓存卡片',
        body: '离线可读的正文',
        attribution: '维基文库',
        fetchedAt: DateTime.now(),
      ),
    );
    final FeedRepository repository = buildRepository(
      cache: cache,
      settings: const AppSettings(enabledSources: <CardKind>{CardKind.poetry}),
      adapters: <CardKind, CardAdapter>{
        CardKind.poetry: _FailingAdapter(CardKind.poetry, '诗词名句'),
      },
    );

    final FeedFetchResult result = await repository.nextCard();
    expect(result.fromCache, isTrue);
    expect(result.card.id, 'cached:1');
  });

  test('兔子洞：深度超过上限时拒绝', () async {
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(),
      adapters: <CardKind, CardAdapter>{},
    );
    final TextCard parent = TextCard(
      id: 'wiki:deep',
      kind: CardKind.wikiTerm,
      title: '深层词条',
      body: '正文',
      attribution: '维基百科',
      depth: TextCard.maxDepth,
      links: const <CardLink>[CardLink(label: '下一个', title: '下一个')],
      fetchedAt: DateTime.now(),
    );
    await expectLater(
      repository.digDeeper(parent, parent.links.first),
      throwsA(isA<SourceException>()),
    );
  });

  test('全部内容源关闭时抛出可读错误', () async {
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(enabledSources: <CardKind>{}),
      adapters: <CardKind, CardAdapter>{},
    );
    await expectLater(
      repository.nextCard(),
      throwsA(
        isA<SourceException>().having(
          (SourceException e) => e.message,
          'message',
          contains('关闭全部内容源'),
        ),
      ),
    );
  });

  test('英文占比为零时不会请求英文，切换到百分百后才请求英文', () async {
    final _OkAdapter adapter = _OkAdapter(CardKind.prose, '短篇小说');
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(
        enabledSources: <CardKind>{CardKind.prose},
        englishPercent: 0,
      ),
      adapters: <CardKind, CardAdapter>{CardKind.prose: adapter},
    );

    await repository.nextCard();
    expect(adapter.lastPreferEnglish, isFalse);
    repository.updateSettings(
      const AppSettings(
        enabledSources: <CardKind>{CardKind.prose},
        englishPercent: 100,
      ),
    );
    await repository.nextCard();
    expect(adapter.lastPreferEnglish, isTrue);
  });

  test('英文占比为零时离线缓存也不会返回英文卡片', () async {
    final CardCache cache = await buildCache();
    await cache.save(
      TextCard(
        id: 'prose:en:cached',
        kind: CardKind.prose,
        title: 'English cache',
        subtitle: 'English',
        body: 'cached',
        attribution: 'test',
        fetchedAt: DateTime.now(),
      ),
    );
    await cache.save(
      TextCard(
        id: 'prose:zh:cached',
        kind: CardKind.prose,
        title: '中文缓存',
        subtitle: '中文',
        body: '缓存正文',
        attribution: 'test',
        fetchedAt: DateTime.now(),
      ),
    );
    final FeedRepository repository = buildRepository(
      cache: cache,
      settings: const AppSettings(
        enabledSources: <CardKind>{CardKind.prose},
        englishPercent: 0,
      ),
      adapters: <CardKind, CardAdapter>{
        CardKind.prose: _FailingAdapter(CardKind.prose, '短篇小说'),
      },
    );

    final FeedFetchResult result = await repository.nextCard();
    expect(result.fromCache, isTrue);
    expect(result.card.isEnglish, isFalse);
  });

  test('六个内容源轮换时不会被最快的诗词接口垄断', () async {
    final Map<CardKind, CardAdapter> adapters = <CardKind, CardAdapter>{
      for (final CardKind kind in CardKind.values)
        kind: _OkAdapter(kind, kind.label),
    };
    final FeedRepository repository = buildRepository(
      cache: await buildCache(),
      settings: const AppSettings(),
      adapters: adapters,
    );

    final List<CardKind> kinds = <CardKind>[];
    for (var i = 0; i < CardKind.values.length; i++) {
      kinds.add((await repository.nextCard()).card.kind);
    }
    expect(kinds.toSet(), hasLength(CardKind.values.length));
  });
}
