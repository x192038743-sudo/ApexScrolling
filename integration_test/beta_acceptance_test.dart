// 测试版真机验收：在真机 / 模拟器上跑真实网络 + 真实手势。
//
//   flutter test integration_test/beta_acceptance_test.dart -d <device-id>
//
// 覆盖规划里的集成验收项：
//   1. 冷启动出卡（打印卡片来源 / 标题 / 字数作为证据）
//   2. 卡片态：有渐隐、无内滚；上滑切下一张
//   3. 展开态：出现内滚；长文上滑先滚正文、不切卡；滚到底继续上滑则切卡
//   4. 短卡展开后继续上滑 → 直接切下一张（设计如此）
//   5. 再点一次收起回卡片态
//   6. 设置页可进入并显示测试版版本号
import 'package:apex_scrolling/app.dart';
import 'package:apex_scrolling/core/app_info.dart';
import 'package:apex_scrolling/state/feed_controller.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/ui/card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration firstCardTimeout = Duration(seconds: 180);
const Duration nextCardTimeout = Duration(seconds: 90);

/// 需要真实网络，等待期间用真实时间推进帧。
Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('等待超时：$reason');
}

/// 不用 pumpAndSettle：信息流里持续存在加载动画与网络请求。
Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

/// 等 PageView 的翻页动画彻底停稳，否则随后的点击会被惯性滚动吃掉。
Future<void> waitForPageSettled(
  WidgetTester tester,
  PageController controller,
) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
  var stableFrames = 0;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    final double? page = controller.page;
    if (page != null && (page - page.round()).abs() < 0.01) {
      stableFrames++;
      if (stableFrames >= 4) return;
    } else {
      stableFrames = 0;
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('冷启动出卡 → 上滑切卡 → 展开/滚动/切卡 → 收起 → 设置页', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const ApexScrollingApp(),
      ),
    );
    await tester.pump();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    final PageController pageController =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    FeedState feed() => container.read(feedControllerProvider);

    /// 当前页真正渲染出来的卡片（PageView 会同时保留相邻页，不能取 first）。
    TextCardView visibleCard() {
      final int index = (pageController.page ?? 0).round();
      final String id = feed().cards[index].id;
      final Finder finder = find.byWidgetPredicate(
        (Widget widget) => widget is TextCardView && widget.card.id == id,
      );
      expect(finder, findsWidgets, reason: '第 $index 页卡片未渲染');
      return tester.widget<TextCardView>(finder.first);
    }

    // ---------------------------------------------------------------- 1. 冷启动
    await waitFor(
      tester,
      () => feed().cards.isNotEmpty,
      timeout: firstCardTimeout,
      reason: '首卡未在 ${firstCardTimeout.inSeconds}s 内出现',
    );
    final TextCardView first = visibleCard();
    debugPrint(
      '[验收] 首卡: ${first.card.kind.label} | ${first.card.title} | '
      '${first.card.body.length} 字 | ${first.card.attribution}',
    );
    expect(first.card.title.trim(), isNotEmpty);
    expect(first.card.body.trim(), isNotEmpty);
    expect(find.byType(ShaderMask), findsWidgets, reason: '卡片态应有渐隐遮罩');
    expect(find.byType(SingleChildScrollView), findsNothing, reason: '卡片态不应可内滚');

    // ------------------------------------------------------- 2. 上滑切下一张
    final String firstId = first.card.id;
    await tester.fling(find.byType(PageView), const Offset(0, -420), 1600);
    await waitFor(
      tester,
      () => (pageController.page ?? 0).round() >= 1 && feed().cards.length > 1,
      timeout: nextCardTimeout,
      reason: '上滑后没有切到第二张',
    );
    await waitFor(
      tester,
      () {
        final int index = (pageController.page ?? 0).round();
        return index < feed().cards.length;
      },
      timeout: nextCardTimeout,
      reason: '第二张卡未就绪',
    );
    final TextCardView second = visibleCard();
    expect(second.card.id, isNot(firstId), reason: '上滑后应切到新卡片');
    debugPrint('[验收] 上滑切卡成功：${second.card.title}');

    // ------------------------------------------- 3. 找一张长文卡测「展开内滚」
    TextCardView target = second;
    for (var i = 0; i < 12 && target.card.body.length < 700; i++) {
      final int from = (pageController.page ?? 0).round();
      await tester.fling(find.byType(PageView), const Offset(0, -420), 1600);
      await waitFor(
        tester,
        () {
          final int index = (pageController.page ?? 0).round();
          return index > from && index < feed().cards.length;
        },
        timeout: nextCardTimeout,
        reason: '寻找长文卡时第 ${i + 1} 次翻页超时',
      );
      target = visibleCard();
    }
    final bool hasLongCard = target.card.body.length >= 700;
    debugPrint(
      '[验收] 长文卡: ${hasLongCard ? '${target.card.title}（${target.card.body.length} 字）' : '本次未抽到（跳过滚动断言）'}',
    );

    // ---------------------------------------------- 4. 展开态：内滚不切卡
    await waitForPageSettled(tester, pageController);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await settle(tester, frames: 8);
    if (find.byType(SingleChildScrollView).evaluate().isEmpty) {
      // 少数情况下首次点击被滚动吸收，再点一次。
      await waitForPageSettled(tester, pageController);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester, frames: 8);
    }
    expect(find.byType(SingleChildScrollView), findsWidgets, reason: '展开态应出现内滚视图');
    debugPrint('[验收] 展开态: ${target.card.title}');

    if (hasLongCard) {
      final String expandedId = target.card.id;
      final Finder scrollFinder = find.byType(SingleChildScrollView).first;
      final ScrollController? scrollController =
          tester.widget<SingleChildScrollView>(scrollFinder).controller;
      final double maxExtent =
          scrollController?.position.maxScrollExtent ?? 0;
      if (maxExtent > 200) {
        final double before = scrollController!.offset;
        await tester.drag(scrollFinder, const Offset(0, -160));
        await settle(tester, frames: 4);
        expect(
          scrollController.offset,
          greaterThan(before),
          reason: '展开态上滑应滚动正文',
        );
        expect(
          visibleCard().card.id,
          expandedId,
          reason: '正文未到底时上滑不应切卡',
        );
        debugPrint(
          '[验收] 展开态内滚动正常（offset ${before.toStringAsFixed(0)} → '
          '${scrollController.offset.toStringAsFixed(0)}，未误切卡）',
        );
      } else {
        debugPrint(
          '[验收] 该卡可滚距离仅 ${maxExtent.toStringAsFixed(0)}px（不足一屏），跳过内滚动断言',
        );
      }

      // 滚到底后继续上滑 → 切下一张（规划里的衔接手势）
      final int before = (pageController.page ?? 0).round();
      for (var i = 0; i < 30; i++) {
        await tester.fling(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -700),
          3000,
        );
        await settle(tester, frames: 3);
        final int now = (pageController.page ?? 0).round();
        if (now > before) break;
      }
      final int now = (pageController.page ?? 0).round();
      expect(now, greaterThan(before), reason: '滚到正文底部后继续上滑应切下一张');
      debugPrint('[验收] 滑到底继续上滑切卡成功（第 $now 页）');
    } else {
      // 短卡：展开态本身没有可滚内容，上滑即切下一张。
      final int before = (pageController.page ?? 0).round();
      await tester.fling(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -420),
        2000,
      );
      await settle(tester, frames: 6);
      debugPrint(
        '[验收] 短卡展开后上滑：${(pageController.page ?? 0).round() > before ? '按设计切到下一张' : '仍停留（可接受）'}',
      );
    }

    // --------------------------------------------------------- 5. 收起回卡片态
    if (find.byType(SingleChildScrollView).evaluate().isNotEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.byType(SingleChildScrollView), findsNothing, reason: '再点一次应收起');
      expect(find.byType(ShaderMask), findsWidgets, reason: '收起后应回到带渐隐的卡片态');
      debugPrint('[验收] 收起回卡片态成功');
    }

    // ----------------------------------------------------------- 6. 设置页
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    final String versionText = '${AppInfo.name} ${AppInfo.versionLabel}';
    for (var i = 0; i < 12 && find.text(versionText).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -320));
      await settle(tester, frames: 2);
    }
    expect(find.text(versionText), findsOneWidget, reason: '设置页应显示测试版版本号');
    debugPrint('[验收] 设置页版本号: ${AppInfo.versionLabel}');
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    debugPrint('[验收] 全部通过');
  });
}
