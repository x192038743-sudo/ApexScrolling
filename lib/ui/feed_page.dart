import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../models/app_settings.dart';
import '../models/text_card.dart';
import '../state/feed_controller.dart';
import '../state/providers.dart';
import 'card_view.dart';
import 'settings_page.dart';
import 'theme.dart';

/// 信息流主页：上下滑动刷卡片 + 预取 + 兔子洞。
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final PageController _pageController = PageController();
  int _index = 0;
  bool _showHint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(feedControllerProvider.notifier).ensurePrefetch(0);
    });
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    ref.read(feedControllerProvider.notifier).ensurePrefetch(index);
  }

  void _goToNext() {
    if (!_pageController.hasClients) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openLink(int index, CardLink link) async {
    final TextCard? card = await ref
        .read(feedControllerProvider.notifier)
        .openLink(index, link);
    if (card != null && mounted) {
      // 等插入后的列表渲染完成再翻页，保证能滑到新卡片。
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _goToNext();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FeedState state = ref.watch(feedControllerProvider);
    final AppSettings settings = ref.watch(settingsControllerProvider);
    final AppPalette palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: state.cards.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index >= state.cards.length) {
                return _LoaderPage(
                  loading: state.loading,
                  message: state.message,
                  palette: palette,
                  scale: settings.fontScale,
                  onRetry: () => ref
                      .read(feedControllerProvider.notifier)
                      .ensurePrefetch(index),
                );
              }
              final TextCard card = state.cards[index];
              return TextCardView(
                key: ValueKey<String>(card.id),
                card: card,
                isCurrent: index == _index,
                settings: settings,
                onNext: _goToNext,
                onOpenLink: (CardLink link) => _openLink(index, link),
              );
            },
          ),
          _TopBar(palette: palette, onSettings: _openSettings),
          if (state.message != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 44,
              left: 0,
              right: 0,
              child: Center(
                child: _Notice(text: state.message!, palette: palette),
              ),
            ),
          if (_showHint && state.cards.isNotEmpty)
            Positioned(
              right: 26,
              bottom: 96,
              child: _Hint(text: '上滑下一张 · 轻点展开', palette: palette),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.palette, required this.onSettings});

  final AppPalette palette;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 10, 12, 0),
        child: Row(
          children: <Widget>[
            Text(
              'APEX SCROLLING',
              style: AppTextStyles.meta(1, palette).copyWith(
                letterSpacing: 3.4,
                fontSize: 10.5,
                color: palette.muted.withValues(alpha: 0.75),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onSettings,
              iconSize: 19,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: Icon(
                Icons.tune_rounded,
                color: palette.muted.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 末尾加载页：不是卡片，允许出现极简的重试入口。
class _LoaderPage extends StatelessWidget {
  const _LoaderPage({
    required this.loading,
    required this.message,
    required this.palette,
    required this.scale,
    required this.onRetry,
  });

  final bool loading;
  final String? message;
  final AppPalette palette;
  final double scale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppTextStyles.meta(scale, palette);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: loading
                ? CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: palette.muted.withValues(alpha: 0.7),
                  )
                : null,
          ),
          const SizedBox(height: 18),
          Text(
            message ?? (loading ? '正在取下一张…' : '继续上滑加载'),
            style: style.copyWith(height: 1.8),
            textAlign: TextAlign.center,
          ),
          if (!loading) ...<Widget>[
            const SizedBox(height: 14),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Text(
                '重试',
                style: style.copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.meta(1, palette).copyWith(
        fontSize: 11,
        color: palette.muted.withValues(alpha: 0.55),
      ),
    );
  }
}

/// 顶部提示条：离线 / 数据源不可用时的轻提示。
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
      ),
      child: Text(
        text,
        style: AppTextStyles.meta(1, palette).copyWith(
          fontSize: 11.5,
          color: palette.muted,
        ),
      ),
    );
  }
}
