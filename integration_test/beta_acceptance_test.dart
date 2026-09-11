// 测试版真机验收：在真机 / 模拟器上跑真实网络 + 真实手势。
//
//   flutter test integration_test/beta_acceptance_test.dart -d <device-id>
//
// 覆盖计划书里的「集成验收」项：冷启动出卡、上滑切卡、点击展开 / 收起、
// 展开态内滚动、设置页可进入且显示测试版版本号。
import 'package:apex_scrolling/app.dart';
import 'package:apex_scrolling/core/app_info.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/ui/card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首卡耗时最坏情况：冷启动抽到 Wikidata 词条源（约 10–20s）+ 网络抖动。
const Duration _firstCardTimeout = Duration(seconds: 150);

/// 需要真实网络，等待期间用真实时间推进帧。
Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  String? reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('等待超时${reason == null ? '' : '：$reason'}');
}

/// 推进若干帧（不用 pumpAndSettle：信息流可能有持续动画）。
Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('冷启动出卡 → 上滑切卡 → 点击展开/收起 → 设置页', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const ApexScrollingApp(),
      ),
    );
    await tester.pump();

    // 1. 冷启动拿到第一张卡（真实网络）。
    await waitFor(
      tester,
      () => find.byType(TextCardView).evaluate().isNotEmpty,
      timeout: _firstCardTimeout,
      reason: '首卡未在 ${_firstCardTimeout.inSeconds}s 内出现',
    );
    final TextCardView firstCard =
        tester.widget<TextCardView>(find.byType(TextCardView).first);
    debugPrint(
      '[验收] 首卡: ${firstCard.card.kind.label} | ${firstCard.card.title} | '
      '${firstCard.card.body.length} 字 | ${firstCard.card.attribution}',
    );
    expect(firstCard.card.title.trim(), isNotEmpty);
    expect(firstCard.card.body.trim(), isNotEmpty);
    // 卡片态：有渐隐遮罩、无内滚视图。
    expect(find.byType(ShaderMask), findsWidgets);
    expect(find.byType(SingleChildScrollView), findsNothing);

    // 2. 上滑切下一张。
    await tester.fling(find.byType(PageView), const Offset(0, -420), 1400);
    await waitFor(
      tester,
      () {
        final Finder cards = find.byType(TextCardView);
        if (cards.evaluate().length < 2) {
          // 预取可能还没落地，继续等下一页进入视口。
          return find.text(firstCard.card.title).evaluate().isEmpty;
        }
        final TextCardView visible =
            tester.widget<TextCardView>(cards.first);
        return visible.card.id != firstCard.card.id;
      },
      timeout: const Duration(seconds: 90),
      reason: '上滑后没有切换到下一张卡',
    );
    debugPrint('[验收] 上滑切卡成功');

    // 3. 点击中央进入展开态：出现内滚视图与「轻点收起」提示。
    final TextCardView current =
        tester.widget<TextCardView>(find.byType(TextCardView).first);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    debugPrint('[验收] 展开态: ${current.card.title}');

    // 4. 展开态内滚动仍停留在同一张卡。
    await tester.fling(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -260),
      1500,
    );
    await tester.pump(const Duration(milliseconds: 600));
    final TextCardView afterScroll =
        tester.widget<TextCardView>(find.byType(TextCardView).first);
    expect(afterScroll.card.id, current.card.id);

    // 5. 再点一次收起。
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SingleChildScrollView), findsNothing);
    debugPrint('[验收] 收起回卡片态成功');

    // 6. 设置页：能进入、显示测试版版本号、能返回。
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    final String versionText = '${AppInfo.name} ${AppInfo.versionLabel}';
    for (var i = 0; i < 10 && find.text(versionText).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -320));
      await settle(tester, frames: 2);
    }
    expect(find.text(versionText), findsOneWidget);
    debugPrint('[验收] 设置页版本号: ${AppInfo.versionLabel}');
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    debugPrint('[验收] 全部通过');
  });
}
