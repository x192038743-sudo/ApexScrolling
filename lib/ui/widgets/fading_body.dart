import 'package:flutter/material.dart';

/// 卡片态正文：自适应行数铺满单屏 + 向底部渐变透明淡出。
///
/// 展开态不使用本组件（改为可滚动全文）。
class FadingBody extends StatelessWidget {
  const FadingBody({
    super.key,
    required this.text,
    required this.style,
    this.fadeLines = 1.7,
  });

  final String text;
  final TextStyle style;

  /// 渐变覆盖的行数（越大越柔和）。
  final double fadeLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (text.trim().isEmpty) return const SizedBox.shrink();
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: null,
        )..layout(maxWidth: constraints.maxWidth);
        final double lineHeight = painter.preferredLineHeight <= 0
            ? (style.fontSize ?? 18) * (style.height ?? 1.6)
            : painter.preferredLineHeight;
        final int maxLines =
            (constraints.maxHeight / lineHeight).floor().clamp(1, 200);
        final double fadeStart =
            (((maxLines - fadeLines + 0.6) * lineHeight) / constraints.maxHeight)
                .clamp(0.35, 0.94);

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (Rect rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: <double>[0.0, fadeStart, 1.0],
          ).createShader(rect),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              text,
              style: style,
              maxLines: maxLines,
              overflow: TextOverflow.clip,
              softWrap: true,
            ),
          ),
        );
      },
    );
  }
}
