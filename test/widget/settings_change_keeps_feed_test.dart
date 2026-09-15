// 回归测试：改设置（字号 / 主题 / 源开关）后返回主页，信息流不能被清空。
//
// 曾经的缺陷：feedRepositoryProvider 用 ref.watch 订阅设置，任何设置变更都会
// 重建仓库 → FeedController 被重建 → FeedState 重置 → PageView 停在越界页，
// 返回主页只剩底色（灰屏）。
import 'package:apex_scrolling/data/adapters/card_adapter.dart';
import 'package:apex_scrolling/data/card_cache.dart';
import 'package:apex_scrolling/data/feed_repository.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/ui/card_view.dart';
import 'package:apex_scrolling/ui/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_utils.dart';

/// 无限产出假卡片，便于验证"设置变化不打断信息流"。
class _CannedAdapter implements CardAdapter {
  _CannedAdapter(this.kind);

  @override
  final CardKind kind;

  int calls = 0;

  @override
  String get displayName => kind.label;

  @override
  Future<TextCard> fetch({bool preferEnglish = false}) async {
    calls++;
    return TextCard(
      id: '${kind.id}:$calls',
      kind: kind,
      title: '卡片 $calls',
      subtitle: '测试来源',
      body: '这是一段用于回归测试的正文。' * 4,
      attribution: '测试署名',
      fetchedAt: DateTime.now(),
    );
  }
}

/// 推进若干帧（不用 pumpAndSettle：信息流里可能有加载动画）。
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<({ProviderContainer container, FeedRepository repository})>
harness() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FeedRepository repository = FeedRepository(
    net: NetClient(
      client: MockClient((http.Request request) async => emptyResponse()),
    ),
    cache: CardCache(prefs),
    settings: const AppSettings(
      enabledSources: <CardKind>{CardKind.poetry, CardKind.howTo},
    ),
    adapters: <CardKind, CardAdapter>{
      CardKind.poetry: _CannedAdapter(CardKind.poetry),
      CardKind.howTo: _CannedAdapter(CardKind.howTo),
    },
  );
  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      feedRepositoryProvider.overrideWith((Ref ref) => repository),
    ],
  );
  return (container: container, repository: repository);
}

void main() {
  testWidgets('改字号 / 主题 / 源开关后返回主页，信息流保持不丢', (WidgetTester tester) async {
    // 设置页较长，把视口调高，保证分区都已构建、可直接点击。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ({ProviderContainer container, FeedRepository repository}) h =
        await harness();
    addTearDown(h.container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: FeedPage()),
      ),
    );
    for (
      var i = 0;
      i < 30 && h.container.read(feedControllerProvider).cards.isEmpty;
      i++
    ) {
      await settle(tester, frames: 2);
    }
    await settle(tester);

    // 上滑到第 3 张，记录此刻的卡片数量。
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(0, -420), 1400);
      await settle(tester, frames: 10);
    }
    final PageController pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final int currentIndex = pageController.page!.round();
    final String currentId = h.container
        .read(feedControllerProvider)
        .cards[currentIndex]
        .id;
    expect(
      find.byKey(ValueKey<String>(currentId)),
      findsOneWidget,
      reason: '应已滑到第 3 张',
    );
    final int cardsBefore = h.container
        .read(feedControllerProvider)
        .cards
        .length;
    expect(cardsBefore, greaterThanOrEqualTo(3));

    // ---- 1) 改字号（用户报告的灰屏场景）----
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester, frames: 10);
    await tester.tap(find.text('大'));
    await settle(tester, frames: 6);
    await tester.pageBack();
    await settle(tester, frames: 10);

    expect(
      h.container.read(settingsControllerProvider).fontScaleLevel,
      2,
      reason: '字号应已切到大',
    );
    expect(
      h.container.read(feedControllerProvider).cards.length,
      cardsBefore,
      reason: '改字号不应重建控制器导致卡片被清空',
    );
    expect(find.byType(TextCardView), findsWidgets, reason: '改字号后应仍有卡片在渲染');
    expect(
      find.byKey(ValueKey<String>(currentId)),
      findsOneWidget,
      reason: '应仍停在第 3 张卡',
    );

    // ---- 2) 切主题 ----
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester, frames: 10);
    await tester.tap(find.text('深色'));
    await settle(tester, frames: 6);
    await tester.pageBack();
    await settle(tester, frames: 10);
    expect(
      h.container.read(feedControllerProvider).cards.length,
      cardsBefore,
      reason: '切主题不应清空信息流',
    );
    expect(find.byKey(ValueKey<String>(currentId)), findsOneWidget);

    // ---- 3) 切源开关（关掉一个源）----
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester, frames: 10);
    final Finder howToTile = find.ancestor(
      of: find.text(CardKind.howTo.label),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(howToTile);
    await settle(tester, frames: 6);
    await tester.pageBack();
    await settle(tester, frames: 10);
    expect(
      h.container.read(feedControllerProvider).cards.length,
      cardsBefore,
      reason: '关闭一个内容源不应清空已有卡片',
    );
    expect(find.byKey(ValueKey<String>(currentId)), findsOneWidget);
  });
}
