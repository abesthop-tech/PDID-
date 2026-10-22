class CurationItem {
  final String id;
  final String category; // 'ai_news' | 'deals' | 'reading'
  final String title;
  final String summary;
  final String whyItMatters;
  final String url;
  final String sourceName;
  final String publishedAt;
  final List<String> tags;
  final String? priceOrDiscountBadge;
  final bool isSavedToObsidian;

  const CurationItem({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.whyItMatters,
    required this.url,
    required this.sourceName,
    required this.publishedAt,
    this.tags = const [],
    this.priceOrDiscountBadge,
    this.isSavedToObsidian = false,
  });

  String get categoryLabel {
    switch (category) {
      case 'ai_news':
        return '🤖 ローカルAI・開発ツール解説';
      case 'deals':
        return '🏷️ お得情報・セール・三茶/都内スポット';
      case 'reading':
        return '📚 良記事・哲学・創作読み物';
      default:
        return '✨ AIキュレーション';
    }
  }

  CurationItem copyWith({
    String? id,
    String? category,
    String? title,
    String? summary,
    String? whyItMatters,
    String? url,
    String? sourceName,
    String? publishedAt,
    List<String>? tags,
    String? priceOrDiscountBadge,
    bool? isSavedToObsidian,
  }) {
    return CurationItem(
      id: id ?? this.id,
      category: category ?? this.category,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      whyItMatters: whyItMatters ?? this.whyItMatters,
      url: url ?? this.url,
      sourceName: sourceName ?? this.sourceName,
      publishedAt: publishedAt ?? this.publishedAt,
      tags: tags ?? this.tags,
      priceOrDiscountBadge: priceOrDiscountBadge ?? this.priceOrDiscountBadge,
      isSavedToObsidian: isSavedToObsidian ?? this.isSavedToObsidian,
    );
  }

  factory CurationItem.fromJson(Map<String, dynamic> json) {
    final rawTags = <String>[];
    if (json['tags'] is List) {
      for (final t in (json['tags'] as List)) {
        rawTags.add(t.toString());
      }
    }

    return CurationItem(
      id: (json['id'] ?? json['title'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      category: (json['category'] ?? 'ai_news').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? json['description'] ?? '').toString(),
      whyItMatters: (json['why_it_matters'] ??
              json['whyItMatters'] ??
              json['personal_relevance'] ??
              'あなたのObsidianプロファイル（ローカルAI・制作・コスパ重視）に関連度が高いトピックです。')
          .toString(),
      url: (json['url'] ?? 'https://example.com').toString(),
      sourceName: (json['source_name'] ?? json['sourceName'] ?? 'AI Concierge Picks').toString(),
      publishedAt: (json['published_at'] ?? json['publishedAt'] ?? '今日').toString(),
      tags: rawTags,
      priceOrDiscountBadge:
          json['price_or_discount_badge']?.toString() ?? json['badge']?.toString(),
      isSavedToObsidian: json['is_saved_to_obsidian'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'summary': summary,
        'why_it_matters': whyItMatters,
        'url': url,
        'source_name': sourceName,
        'published_at': publishedAt,
        'tags': tags,
        'price_or_discount_badge': priceOrDiscountBadge,
        'is_saved_to_obsidian': isSavedToObsidian,
      };
}
