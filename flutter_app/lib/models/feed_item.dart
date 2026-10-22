class FeedItem {
  final String id;
  final String sourceId;
  final String sourceName;
  final String platform; // 'youtube' | 'pixiv' | 'x' | 'rss' | 'custom'
  final String title;
  final String summary;
  final String url;
  final String author;
  final String publishedAt;
  final String? thumbnailUrl;
  final List<String> tags;
  final bool isRead;
  final bool isSavedToObsidian;

  const FeedItem({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.platform,
    required this.title,
    required this.summary,
    required this.url,
    required this.author,
    required this.publishedAt,
    this.thumbnailUrl,
    this.tags = const [],
    this.isRead = false,
    this.isSavedToObsidian = false,
  });

  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return 'YouTube';
      case 'pixiv':
        return 'Pixiv';
      case 'x':
      case 'twitter':
        return 'X (Twitter)';
      case 'rss':
        return 'RSS / Blog';
      default:
        return 'Web差分';
    }
  }

  FeedItem copyWith({
    String? id,
    String? sourceId,
    String? sourceName,
    String? platform,
    String? title,
    String? summary,
    String? url,
    String? author,
    String? publishedAt,
    String? thumbnailUrl,
    List<String>? tags,
    bool? isRead,
    bool? isSavedToObsidian,
  }) {
    return FeedItem(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      platform: platform ?? this.platform,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      url: url ?? this.url,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      tags: tags ?? this.tags,
      isRead: isRead ?? this.isRead,
      isSavedToObsidian: isSavedToObsidian ?? this.isSavedToObsidian,
    );
  }

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    final rawTags = <String>[];
    if (json['tags'] is List) {
      for (final t in (json['tags'] as List)) {
        rawTags.add(t.toString());
      }
    }

    return FeedItem(
      id: (json['id'] ?? json['url'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      sourceId: (json['source_id'] ?? json['sourceId'] ?? 'default').toString(),
      sourceName: (json['source_name'] ?? json['sourceName'] ?? '監視ソース').toString(),
      platform: (json['platform'] ?? json['source_type'] ?? 'custom').toString().toLowerCase(),
      title: (json['title'] ?? '無題の更新').toString(),
      summary: (json['summary'] ?? json['description'] ?? json['content_preview'] ?? '').toString(),
      url: (json['url'] ?? json['link'] ?? 'https://example.com').toString(),
      author: (json['author'] ?? json['source_name'] ?? '').toString(),
      publishedAt: (json['published_at'] ?? json['publishedAt'] ?? '今日').toString(),
      thumbnailUrl: json['thumbnail_url']?.toString() ?? json['thumbnailUrl']?.toString(),
      tags: rawTags,
      isRead: json['is_read'] == true || json['isRead'] == true,
      isSavedToObsidian: json['is_saved_to_obsidian'] == true || json['isSavedToObsidian'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_id': sourceId,
        'source_name': sourceName,
        'platform': platform,
        'title': title,
        'summary': summary,
        'url': url,
        'author': author,
        'published_at': publishedAt,
        'thumbnail_url': thumbnailUrl,
        'tags': tags,
        'is_read': isRead,
        'is_saved_to_obsidian': isSavedToObsidian,
      };
}

class CustomUrlRule {
  final String strategy; // 'rss_auto' | 'css_selector' | 'gemini_extract' | 'api_adapter'
  final String? itemSelector;
  final String? titleSelector;
  final String? linkSelector;
  final String? extractionPrompt;
  final String description;

  const CustomUrlRule({
    required this.strategy,
    this.itemSelector,
    this.titleSelector,
    this.linkSelector,
    this.extractionPrompt,
    required this.description,
  });

  factory CustomUrlRule.fromJson(Map<String, dynamic> json) {
    return CustomUrlRule(
      strategy: (json['strategy'] ?? json['method'] ?? 'gemini_extract').toString(),
      itemSelector: json['item_selector']?.toString() ?? json['itemSelector']?.toString(),
      titleSelector: json['title_selector']?.toString() ?? json['titleSelector']?.toString(),
      linkSelector: json['link_selector']?.toString() ?? json['linkSelector']?.toString(),
      extractionPrompt: json['extraction_prompt']?.toString() ?? json['extractionPrompt']?.toString(),
      description: (json['description'] ?? 'AI自動生成ルール').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'strategy': strategy,
        'item_selector': itemSelector,
        'title_selector': titleSelector,
        'link_selector': linkSelector,
        'extraction_prompt': extractionPrompt,
        'description': description,
      };
}

class WatchSource {
  final String id;
  final String name;
  final String platform; // 'youtube' | 'pixiv' | 'x' | 'rss' | 'custom'
  final String url;
  final String instruction;
  final CustomUrlRule rule;
  final bool enabled;
  final String lastCheckedAt;
  final int unreadCount;

  const WatchSource({
    required this.id,
    required this.name,
    required this.platform,
    required this.url,
    required this.instruction,
    required this.rule,
    this.enabled = true,
    this.lastCheckedAt = '未取得',
    this.unreadCount = 0,
  });

  factory WatchSource.fromJson(Map<String, dynamic> json) {
    return WatchSource(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      name: (json['name'] ?? json['title'] ?? 'カスタム監視ソース').toString(),
      platform: (json['platform'] ?? json['source_type'] ?? 'custom').toString().toLowerCase(),
      url: (json['url'] ?? '').toString(),
      instruction: (json['instruction'] ?? json['user_instruction'] ?? '最新の新着差分を取得').toString(),
      rule: json['rule'] is Map<String, dynamic>
          ? CustomUrlRule.fromJson(json['rule'] as Map<String, dynamic>)
          : CustomUrlRule(
              strategy: (json['strategy'] ?? 'gemini_extract').toString(),
              itemSelector: json['item_selector']?.toString(),
              extractionPrompt: json['instruction']?.toString(),
              description: (json['rule_description'] ?? '自然言語指示による差分抽出').toString(),
            ),
      enabled: json['enabled'] != false,
      lastCheckedAt: (json['last_checked_at'] ?? json['lastCheckedAt'] ?? '今日 08:30').toString(),
      unreadCount: json['unread_count'] is int
          ? json['unread_count'] as int
          : int.tryParse((json['unread_count'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'url': url,
        'instruction': instruction,
        'rule': rule.toJson(),
        'enabled': enabled,
        'last_checked_at': lastCheckedAt,
        'unread_count': unreadCount,
      };
}
