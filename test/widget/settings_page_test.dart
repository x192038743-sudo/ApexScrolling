import 'package:apex_scrolling/core/app_info.dart';
import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/state/providers.dart';
import 'package:apex_scrolling/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<({Widget widget, ProviderContainer container})> buildSettings() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  return (
    widget: UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ),
    container: container,
  );
}

/// 设置页较长且 ListView 懒构建：把测试视口调高，保证所有分区都已构建。
void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('测试版信息与六个内容源开关都可见', (WidgetTester tester) async {
    useTallView(tester);
    final ({Widget widget, ProviderContainer container}) harness =
        await buildSettings();
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(
      find.text('${AppInfo.name} ${AppInfo.versionLabel}'),
      findsOneWidget,
    );
    expect(AppInfo.isBeta, isTrue);
    expect(AppInfo.versionLabel, contains('测试版'));
    for (final CardKind kind in CardKind.values) {
      expect(find.text(kind.label), findsOneWidget);
    }
    expect(find.byType(SwitchListTile), findsNWidgets(6));
  });

  testWidgets('开关与字号改动即时写回设置', (WidgetTester tester) async {
    useTallView(tester);
    final ({Widget widget, ProviderContainer container}) harness =
        await buildSettings();
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    final Finder poetryTile = find.ancestor(
      of: find.text(CardKind.poetry.label),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(poetryTile);
    await tester.pumpAndSettle();
    expect(
      harness.container
          .read(settingsControllerProvider)
          .isEnabled(CardKind.poetry),
      isFalse,
    );

    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(settingsControllerProvider).fontScaleLevel,
      2,
    );
    expect(
      harness.container.read(settingsControllerProvider).fontScale,
      AppSettings.fontScales[2],
    );
  });

  testWidgets('冷门度可在宽松 / 严格之间切换', (WidgetTester tester) async {
    useTallView(tester);
    final ({Widget widget, ProviderContainer container}) harness =
        await buildSettings();
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('严格（≤20）'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(settingsControllerProvider).wikiRarity,
      WikiRarity.strict,
    );
  });

  testWidgets('清除缓存卡片给出反馈', (WidgetTester tester) async {
    useTallView(tester);
    final ({Widget widget, ProviderContainer container}) harness =
        await buildSettings();
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('清除缓存卡片'));
    await tester.pumpAndSettle();
    expect(find.text('已清除本地缓存卡片'), findsOneWidget);
  });
}
