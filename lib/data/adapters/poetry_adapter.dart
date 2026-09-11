import '../../core/endpoints.dart';
import '../../models/text_card.dart';
import '../net_client.dart';
import 'card_adapter.dart';

/// 诗词名句：今日诗词 API。卡片最短，用来给信息流调节奏。
class PoetryAdapter implements CardAdapter {
  PoetryAdapter(this._net);

  final NetClient _net;

  @override
  CardKind get kind => CardKind.poetry;

  @override
  String get displayName => '诗词名句';

  @override
  Future<TextCard> fetch() async {
    final Map<String, dynamic> json =
        await _net.getJson(Uri.parse(Endpoints.jinrishiciApi));
    final String content = (json['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw SourceException('今日诗词返回空内容');
    }
    final String origin = (json['origin'] ?? '').toString().trim();
    final String author = (json['author'] ?? '').toString().trim();

    return TextCard(
      id: 'poetry:${content.hashCode}',
      kind: kind,
      title: origin.isEmpty ? '诗词名句' : origin,
      subtitle: author.isEmpty ? '今日诗词' : '$author · 今日诗词',
      body: content,
      attribution: AdapterAttribution.jinrishici,
      sourceUrl: 'https://www.jinrishici.com/',
      fetchedAt: DateTime.now(),
    );
  }
}
