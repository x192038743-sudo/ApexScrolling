// 信息流压测：真机 / 模拟器上连续上滑 50 张（对应规划里的集成验收项）。
//
//   flutter test integration_test/feed_soak_test.dart -d <device-id>
//
// 断言：每次上滑都翻到下一张、当前页渲染的是完整卡片（标题/正文非空）、
// 期间不出现异常（不白屏不崩溃），并统计耗时与来源分布。
import 'package:apex_scrolling/app.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/state/feed_controller.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/ui/card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int targetSwipes = 50;
const Duration firstCardTimeout = Duration(seconds: 180);
const Duration nextCardTimeout = Duration(seconds: 90);

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('连续上滑 $targetSwipes 张：不白屏、不崩溃、逐张可读', (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const ApexScrollingApp(),
      ),
    );
    await tester.pump();

    final ProviderContainer container =
        ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    final PageController pageController =
        tester.widget<PageView>(find.byType(PageView)).controller!;

    FeedState feed() => container.read(feedControllerProvider);

    await waitFor(
      tester,
      () => feed().cards.isNotEmpty,
      timeout: firstCardTimeout,
      reason: '首卡未在 ${firstCardTimeout.inSeconds}s 内出现',
    );

    final Map<CardKind, int> kindCount = <CardKind, int>{};
    final List<double> swipeSeconds = <double>[];
    final Stopwatch total = Stopwatch()..start();
    var visitedCards = 1;
    kindCount[feed().cards.first.kind] = 1;

    for (var step = 1; step <= targetSwipes; step++) {
      final int before = visitedCards;
      final Stopwatch one = Stopwatch()..start();
      await tester.fling(find.byType(PageView), const Offset(0, -420), 1600);
      await tester.pump(const Duration(milliseconds: 320));

      await waitFor(
        tester,
        () {
          final double? page = pageController.page;
          if (page == null) return false;
          final int index = page.round();
          final FeedState state = feed();
          // 目标页已经落地成真实卡片（而不是加载页）。
          return index < state.cards.length &&
              state.cards[index].title.trim().isNotEmpty;
        },
        timeout: nextCardTimeout,
        reason: '第 $step 次上滑后第 ${before + 1} 张卡未就绪',
      );

      // 当前页必须渲染的是卡片（不是加载页 / 白屏）。
      final int index = pageController.page!.round();
      final TextCard expected = feed().cards[index];
      final Finder cardFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextCardView && widget.card.id == expected.id,
      );
      expect(cardFinder, findsWidgets, reason: '第 $step 张卡片未渲染：${expected.title}');
      final TextCardView view = tester.widget<TextCardView>(cardFinder.first);
      expect(view.card.body.trim(), isNotEmpty, reason: '第 $step 张卡片正文为空');

      expect(tester.takeException(), isNull, reason: '第 $step 张出现异常');
      one.stop();
      swipeSeconds.add(one.elapsedMilliseconds / 1000);
      kindCount.update(view.card.kind, (int v) => v + 1, ifAbsent: () => 1);
      visitedCards = index + 1;

      if (step % 10 == 0) {
        debugPrint(
          '[soak] 已完成 $step 张，累计 ${total.elapsed.inSeconds}s，'
          '最近一张：${view.card.kind.label} / ${view.card.title}',
        );
      }
    }
    total.stop();

    final double avg = swipeSeconds.reduce((double a, double b) => a + b) /
        swipeSeconds.length;
    final double worst =
        swipeSeconds.reduce((double a, double b) => a > b ? a : b);
    debugPrint(
      '[soak] 结果：$targetSwipes 张卡片，总耗时 ${total.elapsed.inSeconds}s，'
      '平均每张 ${avg.toStringAsFixed(2)}s，最慢 ${worst.toStringAsFixed(2)}s',
    );
    debugPrint(
      '[soak] 来源分布：${kindCount.entries.map((MapEntry<CardKind, int> e) => '${e.key.label}=${e.value}').join('，')}',
    );
    expect(kindCount.length, greaterThan(1), reason: '来源过于单一，可能是某个源一直失败');
  });
}
