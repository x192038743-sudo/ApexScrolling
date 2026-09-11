import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/text_card.dart';
import 'theme.dart';
import 'widgets/fading_body.dart';

/// 一张纯文字卡片：卡片态（单屏 + 渐隐）/ 展开态（内滚全文）。
///
/// 手势：
/// - 卡片态上滑切下一张、下滑回上一张（由外层 PageView 处理）；
/// - 点击卡片进入/退出展开态；
/// - 展开态内滚动，滚到底继续上滑则切下一张；
/// - 底部署名区不响应展开点击（避免误触）。
class TextCardView extends StatefulWidget {
  const TextCardView({
    super.key,
    required this.card,
    required this.isCurrent,
    required this.settings,
    required this.onNext,
    required this.onOpenLink,
  });

  final TextCard card;

  /// 是否为当前页；离开后自动收起回卡片态。
  final bool isCurrent;
  final AppSettings settings;

  /// 展开态滚到底后继续上滑 → 下一张。
  final VoidCallback onNext;

  /// 词条内链（兔子洞）。
  final ValueChanged<CardLink> onOpenLink;

  @override
  State<TextCardView> createState() => _TextCardViewState();
}

class _TextCardViewState extends State<TextCardView> {
  /// 触发切卡的「继续上滑」累计距离。
  static const double _overscrollThreshold = 54;

  bool _expanded = false;
  double _overscroll = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TextCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool changedCard = oldWidget.card.id != widget.card.id;
    final bool leftCurrent = oldWidget.isCurrent && !widget.isCurrent;
    if (_expanded && (changedCard || leftCurrent)) {
      _expanded = false;
      _overscroll = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      _overscroll = 0;
      if (!_expanded && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification ||
        notification is ScrollStartNotification) {
      _overscroll = 0;
      return false;
    }
    if (notification is! OverscrollNotification) return false;
    if (notification.overscroll <= 0) {
      _overscroll = 0;
      return false;
    }
    // 只有已经滑到正文底部才把「继续上滑」交给信息流。
    if (notification.metrics.extentAfter > 0.5) {
      _overscroll = 0;
      return false;
    }
    _overscroll += notification.overscroll;
    if (_overscroll >= _overscrollThreshold) {
      _overscroll = 0;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      setState(() => _expanded = false);
      widget.onNext();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double scale = widget.settings.fontScale;
    final TextStyle titleStyle = AppTextStyles.title(scale, palette);
    final TextStyle bodyStyle = AppTextStyles.body(scale, palette);
    final TextStyle metaStyle = AppTextStyles.meta(scale, palette);
    final double topInset = MediaQuery.paddingOf(context).top + 58;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleExpanded,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(26, topInset, 26, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.card.title, style: titleStyle),
                      if (widget.card.subtitle != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          widget.card.subtitle!,
                          style: metaStyle.copyWith(letterSpacing: 1.1),
                        ),
                      ],
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 0, 26, 92),
                    child: _expanded
                        ? _buildExpandedBody(bodyStyle, metaStyle, palette, scale)
                        : FadingBody(
                            text: widget.card.fullText,
                            style: bodyStyle,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _AttributionBar(
              text: widget.card.attribution,
              hint: _expanded ? '轻点收起' : null,
              style: metaStyle,
              palette: palette,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(
    TextStyle bodyStyle,
    TextStyle metaStyle,
    AppPalette palette,
    double scale,
  ) {
    final List<CardLink> links =
        widget.card.canDigDeeper ? widget.card.links : const <CardLink>[];
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.card.fullText, style: bodyStyle),
            if (links.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              Text(
                widget.card.depth > 0
                    ? '继续深入 · 第 ${widget.card.depth + 1} 层'
                    : '延伸词条',
                style: metaStyle.copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: <Widget>[
                  for (final CardLink link in links)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onOpenLink(link),
                      child: Text(
                        link.label,
                        style: AppTextStyles.link(scale, palette),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// 固定在卡片底部渐变区内的来源署名；不响应展开/收起点击。
class _AttributionBar extends StatelessWidget {
  const _AttributionBar({
    required this.text,
    required this.hint,
    required this.style,
    required this.palette,
  });

  final String text;
  final String? hint;
  final TextStyle style;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              palette.background.withValues(alpha: 0.0),
              palette.background.withValues(alpha: 0.92),
              palette.background,
            ],
            stops: const <double>[0.0, 0.45, 1.0],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                style: style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  hint!,
                  style: style.copyWith(
                    color: style.color?.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
