import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../models/app_settings.dart';
import '../models/text_card.dart';
import '../state/providers.dart';
import '../state/settings_controller.dart';
import 'theme.dart';

/// 设置：逐源开关、字号三档、主题、词条冷门度、缓存与授权说明。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsControllerProvider);
    final SettingsController controller =
        ref.read(settingsControllerProvider.notifier);
    final AppPalette palette = AppPalette.of(context);
    final TextStyle meta = AppTextStyles.meta(1, palette);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
        children: <Widget>[
          _SectionTitle('内容源', palette),
          for (final CardKind kind in CardKind.values)
            SwitchListTile(
              value: settings.isEnabled(kind),
              onChanged: (_) => controller.toggleSource(kind),
              title: Text(kind.label,
                  style: TextStyle(color: palette.text, fontSize: 15)),
              subtitle: Text(
                _sourceDescription(kind),
                style: meta.copyWith(fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          const SizedBox(height: 20),
          _SectionTitle('阅读', palette),
          _Label('字号', palette),
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 0, label: Text('小')),
              ButtonSegment<int>(value: 1, label: Text('标准')),
              ButtonSegment<int>(value: 2, label: Text('大')),
            ],
            selected: <int>{settings.fontScaleLevel},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> value) =>
                controller.setFontScaleLevel(value.first),
          ),
          const SizedBox(height: 18),
          _Label('主题', palette),
          SegmentedButton<AppThemeOption>(
            segments: <ButtonSegment<AppThemeOption>>[
              for (final AppThemeOption option in AppThemeOption.values)
                ButtonSegment<AppThemeOption>(
                  value: option,
                  label: Text(option.label),
                ),
            ],
            selected: <AppThemeOption>{settings.theme},
            showSelectedIcon: false,
            onSelectionChanged: (Set<AppThemeOption> value) =>
                controller.setTheme(value.first),
          ),
          const SizedBox(height: 18),
          _Preview(settings: settings, palette: palette),
          const SizedBox(height: 20),
          _SectionTitle('内容语言', palette),
          _Label('英文内容占比 ${settings.englishPercent}%', palette),
          Slider(
            value: settings.englishPercent.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            label: '${settings.englishPercent}%',
            onChanged: (double value) =>
                controller.setEnglishPercent(value.round()),
          ),
          Text(
            settings.englishPercent == 0
                ? '仅推送中文内容。'
                : '哲学、词条、经典、小说和教程会按此比例优先提供英文内容。诗词保持中文。',
            style: meta.copyWith(fontSize: 12, height: 1.7),
          ),
          const SizedBox(height: 20),
          _SectionTitle('词条冷门程度', palette),
          SegmentedButton<WikiRarity>(
            segments: <ButtonSegment<WikiRarity>>[
              for (final WikiRarity rarity in WikiRarity.values)
                ButtonSegment<WikiRarity>(
                  value: rarity,
                  label: Text('${rarity.label}（≤${rarity.maxSitelinks}）'),
                ),
            ],
            selected: <WikiRarity>{settings.wikiRarity},
            showSelectedIcon: false,
            onSelectionChanged: (Set<WikiRarity> value) =>
                controller.setWikiRarity(value.first),
          ),
          const SizedBox(height: 8),
          Text(
            '站点链接数越少越冷门。宽松档内容更丰富，严格档更「鲜为人知」。',
            style: meta.copyWith(fontSize: 12, height: 1.7),
          ),
          const SizedBox(height: 28),
          _SectionTitle('关于', palette),
          Text(
            '${AppInfo.name} ${AppInfo.versionLabel}',
            style: meta.copyWith(fontSize: 12.5, color: palette.text),
          ),
          const SizedBox(height: 8),
          Text(
            '· 无账号、无埋点、无自建服务器；所有内容来自公开开放资源。\n'
            '· 维基百科 / 维基文库 / 维基教科书：CC BY-SA 4.0\n'
            '· wikiHow：CC BY-NC-SA 3.0（非商业使用）\n'
            '· 古登堡计划：公有领域\n'
            '· 斯坦福哲学百科（SEP）：供个人阅读\n'
            '· 今日诗词：jinrishici.com\n'
            '· 网络不可用时自动回落到本地缓存卡片。',
            style: meta.copyWith(fontSize: 12.5, height: 1.9),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text('返回阅读', style: TextStyle(color: palette.accent)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(cardCacheProvider).clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已清除本地缓存卡片', style: meta)),
                );
              }
            },
            child: Text('清除缓存卡片', style: TextStyle(color: palette.muted)),
          ),
        ],
      ),
    );
  }

  static String _sourceDescription(CardKind kind) {
    switch (kind) {
      case CardKind.wikiTerm:
        return '维基百科 · Wikidata 学术领域 + 站点链接数筛选';
      case CardKind.philosophy:
        return '斯坦福哲学百科条目导语';
      case CardKind.classicExcerpt:
        return '古登堡计划 / 维基文库 · 中文经典与西方哲学';
      case CardKind.prose:
        return '鲁迅、朱自清、契诃夫、爱伦·坡等公版作品片段';
      case CardKind.howTo:
        return 'wikiHow 步骤卡（不可达时用维基教科书）';
      case CardKind.poetry:
        return '今日诗词 · 诗句与出处';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.palette);

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          text,
          style: AppTextStyles.meta(1, palette).copyWith(
            letterSpacing: 2.4,
            fontSize: 11.5,
            color: palette.accent.withValues(alpha: 0.9),
          ),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.palette);

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(color: palette.text, fontSize: 14.5),
        ),
      );
}

/// 排版预览：实时反映字号与主题。
class _Preview extends StatelessWidget {
  const _Preview({required this.settings, required this.palette});

  final AppSettings settings;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '排版预览',
            style: AppTextStyles.meta(settings.fontScale, palette)
                .copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            '我们终此一生，就是要摆脱他人的期待。',
            style: AppTextStyles.body(settings.fontScale, palette),
          ),
        ],
      ),
    );
  }
}
