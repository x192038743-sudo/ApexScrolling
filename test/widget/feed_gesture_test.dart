import 'dart:convert';

import 'package:apex_scrolling/data/adapters/card_adapter.dart';
import 'package:apex_scrolling/data/card_cache.dart';
import 'package:apex_scrolling/data/feed_repository.dart';
import 'package:apex_scrolling/data/net_client.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/state/settings_controller.dart';
import 'package:apex_scrolling/ui/feed_page.dart';
import 'package:apex_scrolling/ui/widgets/fading_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_utils.dart';

/// 无限产出假卡片的适配器（用于手势测试）。
class _CannedAdapter implements CardAdapter {
  _CannedAdapter(this.kind, {this.bodyRepeat = 3, this.extraLinks = false});

  @override
  final CardKind kind;

  /// 正文重复次数：越大越容易触发展开态内滚动。
  final int bodyRepeat;
  final bool extraLinks;

  int calls = 0;

  @override
  String get displayName => kind.label;

  @override
  Future<TextCard> fetch() async {
    calls++;
    return TextCard(
      id: '${kind.id}:$calls',
      kind: kind,
      title: '卡片 $calls',
      subtitle: '测试来源',
      body: '这是一段测试正文。' * bodyRepeat,
      attribution: '测试署名 · CC BY-SA',
      links: extraLinks
          ? const <CardLink>[
              CardLink(label: '组合数', title: '组合数'),
              CardLink(label: '杨辉三角', title: '杨辉三角'),
            ]
          : const <CardLink>[],
      fetchedAt: DateTime.now(),
    );
  }
}

Future<Widget> buildHarness({
  AppSettings settings = const AppSettings(
    enabledSources: <CardKind>{CardKind.poetry},
  ),
  int bodyRepeat = 3,
  bool extraLinks = false,
  Map<CardKind, CardAdapter>? adapters,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    SettingsController.storageKey: jsonEncode(settings.toJson()),
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final CardCache cache = CardCache(prefs);
  final FeedRepository repository = FeedRepository(
    net: NetClient(
      client: MockClient((http.Request request) async => emptyResponse()),
    ),
    cache: cache,
    settings: settings,
    adapters: adapters ??
        <CardKind, CardAdapter>{
          CardKind.poetry: _CannedAdapter(
            CardKind.poetry,
            bodyRepeat: bodyRepeat,
            extraLinks: extraLinks,
          ),
        },
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      feedRepositoryProvider.overrideWith((Ref ref) => repository),
    ],
    child: const MaterialApp(home: FeedPage()),
  );
}

void main() {
  testWidgets('卡片态：上滑切下一张、下滑回上一张', (WidgetTester tester) async {
    await tester.pumpWidget(await buildHarness());
    await tester.pumpAndSettle();
    expect(find.text('卡片 1'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(0, -420), 1400);
    await tester.pumpAndSettle();
    expect(find.text('卡片 2'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(0, 420), 1400);
    await tester.pumpAndSettle();
    expect(find.text('卡片 1'), findsOneWidget);
  });

  testWidgets('卡片态显示渐隐遮罩，展开态移除并可滚动', (WidgetTester tester) async {
    await tester.pumpWidget(await buildHarness(bodyRepeat: 30));
    await tester.pumpAndSettle();

    expect(find.byType(FadingBody), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);

    // 点击正文中央 → 展开
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('轻点收起'), findsOneWidget);

    // 再点一次 → 收起
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.text('轻点收起'), findsNothing);
  });

  testWidgets('展开态滑到正文底部后继续上滑 → 切下一张', (WidgetTester tester) async {
    await tester.pumpWidget(await buildHarness(bodyRepeat: 40));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();
    expect(find.text('卡片 1'), findsOneWidget);

    // 连续上滑直到正文到底并触发切卡。
    for (var i = 0; i < 24; i++) {
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
        4000,
      );
      await tester.pumpAndSettle();
      if (find.text('卡片 2').evaluate().isNotEmpty) break;
    }
    expect(find.text('卡片 2'), findsOneWidget);
    // 切卡后新卡片回到卡片态（渐隐遮罩重新出现）。
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('展开态短正文也能继续上滑切卡', (WidgetTester tester) async {
    await tester.pumpWidget(await buildHarness(bodyRepeat: 1));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();
    expect(find.text('卡片 1'), findsOneWidget);

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
      4000,
    );
    await tester.pumpAndSettle();
    expect(find.text('卡片 2'), findsOneWidget);
  });

  testWidgets('字号三档影响标题字号', (WidgetTester tester) async {
    await tester.pumpWidget(
      await buildHarness(
        settings: const AppSettings(
          enabledSources: <CardKind>{CardKind.poetry},
          fontScaleLevel: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Text title = tester.widget<Text>(find.text('卡片 1'));
    expect(title.style?.fontSize, closeTo(27 * 1.14, 0.01));
  });

  testWidgets('词条内链在展开态可见，点击后插入新卡', (WidgetTester tester) async {
    await tester.pumpWidget(
      await buildHarness(
        bodyRepeat: 6,
        extraLinks: true,
        adapters: <CardKind, CardAdapter>{
          CardKind.poetry: _CannedAdapter(
            CardKind.poetry,
            bodyRepeat: 6,
            extraLinks: true,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();

    expect(find.text('延伸词条'), findsOneWidget);
    expect(find.text('组合数'), findsOneWidget);
  });
}
