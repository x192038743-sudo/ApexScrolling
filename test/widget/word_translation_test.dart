import 'package:apex_scrolling/models/app_settings.dart';
import 'package:apex_scrolling/models/text_card.dart';
import 'package:apex_scrolling/ui/card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('展开态双击英文单词显示翻译气泡', (WidgetTester tester) async {
    final TextCard card = TextCard(
      id: 'prose:en:test',
      kind: CardKind.prose,
      title: 'A test card',
      subtitle: 'English',
      body: 'The ephemeral word appears here.',
      attribution: 'test',
      fetchedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextCardView(
            card: card,
            isCurrent: true,
            settings: const AppSettings(),
            onNext: () {},
            onPrevious: () {},
            onOpenLink: (_) {},
            onTranslateWord: (String word) async => '临时的',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 400));
    await tester.pumpAndSettle();
    final Finder body = find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText && widget.text.toPlainText().startsWith('The'),
    );
    expect(body, findsOneWidget);
    final Offset wordPoint = tester.getCenter(body);
    await tester.tapAt(wordPoint);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(wordPoint);
    await tester.pumpAndSettle();
    expect(find.textContaining('临时的'), findsOneWidget);
  });
}
