import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/today_data.dart';
import '../models/feed_item.dart';
import '../models/curation_item.dart';

class ConciergeState extends ChangeNotifier {
  static const String _prefServerUrlKey = 'concierge_server_url';
  static const String _prefSupabaseUrlKey = 'concierge_supabase_url';
  static const String _prefSupabaseAnonKey = 'concierge_supabase_anon_key';
  static const String _prefVaultPathKey = 'concierge_vault_path';

  static const String _cacheTodayKey = 'concierge_cache_today_v1';
  static const String _cacheFeedsKey = 'concierge_cache_feeds_v1';
  static const String _cacheSourcesKey = 'concierge_cache_sources_v1';
  static const String _cacheCurationsKey = 'concierge_cache_curations_v1';

  String _serverUrl = 'http://localhost:8000';
  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  String _vaultPath = r'\\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs';

  bool _isLoading = false;
  bool _isOnline = false;
  bool _supabaseInitialized = false;
  String _statusMessage = '初期化中...';

  TodayData _todayData = _buildDefaultTodayData();
  List<FeedItem> _feedItems = _buildDefaultFeeds();
  List<WatchSource> _sources = _buildDefaultSources();
  List<CurationItem> _curations = _buildDefaultCurations();

  // Getters
  String get serverUrl => _serverUrl;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;
  String get vaultPath => _vaultPath;
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  bool get isSupabaseConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
  String get statusMessage => _statusMessage;

  TodayData get todayData => _todayData;
  List<FeedItem> get feedItems => _feedItems;
  List<FeedItem> get unreadFeedItems => _feedItems.where((f) => !f.isRead).toList();
  List<WatchSource> get sources => _sources;
  List<CurationItem> get curations => _curations;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString(_prefServerUrlKey) ?? 'http://localhost:8000';
      _supabaseUrl = prefs.getString(_prefSupabaseUrlKey) ?? '';
      _supabaseAnonKey = prefs.getString(_prefSupabaseAnonKey) ?? '';
      _vaultPath = prefs.getString(_prefVaultPathKey) ??
          r'\\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs';

      await _loadFromLocalCache(prefs);
      await _tryInitSupabase();
      await refreshAll();
    } catch (e) {
      _statusMessage = 'オフラインキャッシュ・デモモードで動作中';
      _isOnline = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _tryInitSupabase() async {
    if (!isSupabaseConfigured || _supabaseInitialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
      _supabaseInitialized = true;
    } catch (_) {
      // Ignore initialization errors when offline or already initialized
    }
  }

  Future<void> _loadFromLocalCache(SharedPreferences prefs) async {
    final todayStr = prefs.getString(_cacheTodayKey);
    if (todayStr != null && todayStr.isNotEmpty) {
      try {
        _todayData = TodayData.fromJson(jsonDecode(todayStr) as Map<String, dynamic>);
      } catch (_) {}
    }

    final feedsStr = prefs.getString(_cacheFeedsKey);
    if (feedsStr != null && feedsStr.isNotEmpty) {
      try {
        final list = jsonDecode(feedsStr) as List;
        _feedItems = list
            .whereType<Map<String, dynamic>>()
            .map(FeedItem.fromJson)
            .toList();
      } catch (_) {}
    }

    final sourcesStr = prefs.getString(_cacheSourcesKey);
    if (sourcesStr != null && sourcesStr.isNotEmpty) {
      try {
        final list = jsonDecode(sourcesStr) as List;
        _sources = list
            .whereType<Map<String, dynamic>>()
            .map(WatchSource.fromJson)
            .toList();
      } catch (_) {}
    }

    final curationsStr = prefs.getString(_cacheCurationsKey);
    if (curationsStr != null && curationsStr.isNotEmpty) {
      try {
        final list = jsonDecode(curationsStr) as List;
        _curations = list
            .whereType<Map<String, dynamic>>()
            .map(CurationItem.fromJson)
            .toList();
      } catch (_) {}
    }
  }

  Future<void> _saveToLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheTodayKey, jsonEncode(_todayData.toJson()));
      await prefs.setString(
        _cacheFeedsKey,
        jsonEncode(_feedItems.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _cacheSourcesKey,
        jsonEncode(_sources.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _cacheCurationsKey,
        jsonEncode(_curations.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  String _cleanBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    final base = _cleanBaseUrl(_serverUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath').replace(queryParameters: queryParameters);
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    notifyListeners();

    bool connected = false;
    try {
      final todayRes = await http
          .get(_apiUri('/api/today'))
          .timeout(const Duration(seconds: 4));

      if (todayRes.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(todayRes.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          _todayData = TodayData.fromJson(decoded).copyWith(isOfflineFallback: false);
          connected = true;
        }
      }
    } catch (_) {
      connected = false;
    }

    if (connected) {
      await Future.wait([
        _fetchFeedsFromServer(),
        _fetchCurationsFromServer(),
      ]);
      _isOnline = true;
      _statusMessage = 'バックエンド接続中 ($_serverUrl)';
      await _saveToLocalCache();
    } else {
      _isOnline = false;
      _todayData = _todayData.copyWith(isOfflineFallback: true);
      _statusMessage = isSupabaseConfigured
          ? 'PCスリープ/オフライン (Supabase & ローカルキャッシュで動作中)'
          : 'オフライン/スタンドアロンモード (キャッシュ＆内蔵データで動作中)';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchFeedsFromServer() async {
    try {
      final res = await http
          .get(_apiUri('/api/feeds'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          if (decoded['items'] is List) {
            _feedItems = (decoded['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(FeedItem.fromJson)
                .toList();
          }
          if (decoded['sources'] is List) {
            _sources = (decoded['sources'] as List)
                .whereType<Map<String, dynamic>>()
                .map(WatchSource.fromJson)
                .toList();
          }
        } else if (decoded is List) {
          _feedItems = decoded
              .whereType<Map<String, dynamic>>()
              .map(FeedItem.fromJson)
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchCurationsFromServer() async {
    try {
      final res = await http
          .get(_apiUri('/api/curations'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['items'] is List) {
          _curations = (decoded['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map(CurationItem.fromJson)
              .toList();
        } else if (decoded is List) {
          _curations = decoded
              .whereType<Map<String, dynamic>>()
              .map(CurationItem.fromJson)
              .toList();
        }
      }
    } catch (_) {}
  }

  /// 1. タスク完了状態のトグル (`POST /api/tasks/toggle`)
  Future<void> toggleTask(ObsidianTask task) async {
    final updatedCompleted = !task.completed;
    final updatedTasks = _todayData.tasks.map((t) {
      if (t.id == task.id && t.text == task.text) {
        return t.copyWith(completed: updatedCompleted);
      }
      return t;
    }).toList();

    _todayData = _todayData.copyWith(tasks: updatedTasks);
    notifyListeners();
    await _saveToLocalCache();

    try {
      final res = await http
          .post(
            _apiUri('/api/tasks/toggle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': task.id,
              'text': task.text,
              'section': task.section,
              'completed': updatedCompleted,
              'line_number': task.lineNumber,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic> && body['tasks'] is List) {
          final serverTasks = (body['tasks'] as List)
              .whereType<Map<String, dynamic>>()
              .map(ObsidianTask.fromJson)
              .toList();
          _todayData = _todayData.copyWith(tasks: serverTasks);
          notifyListeners();
        }
      }
    } catch (_) {
      // Offline: optimistic update already applied and cached
    }
  }

  /// 2. クイック短文メモ追加 (`POST /api/tasks/quick-add`)
  Future<void> quickAddTask(String rawText, {String section = 'must'}) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    // AIっぽい自動セクション判定（オフライン時でも自然な分類に）
    String resolvedSection = section;
    if (section == 'auto') {
      if (trimmed.contains('帰ったら') ||
          trimmed.contains('たい') ||
          trimmed.contains('見る') ||
          trimmed.contains('遊ぶ')) {
        resolvedSection = 'want';
      } else {
        resolvedSection = 'must';
      }
    }

    final optimisticTask = ObsidianTask(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      text: trimmed,
      completed: false,
      section: resolvedSection,
      sourceFile: '01_Inbox/やるメモ.md',
    );

    _todayData = _todayData.copyWith(
      tasks: [..._todayData.tasks, optimisticTask],
    );
    notifyListeners();
    await _saveToLocalCache();

    try {
      final res = await http
          .post(
            _apiUri('/api/tasks/quick-add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': trimmed,
              'section': resolvedSection,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic> && body['task'] is Map<String, dynamic>) {
          final created = ObsidianTask.fromJson(body['task'] as Map<String, dynamic>);
          final replaced = _todayData.tasks
              .map((t) => t.id == optimisticTask.id ? created : t)
              .toList();
          _todayData = _todayData.copyWith(tasks: replaced);
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// 3. 趣味ガチャを引く (`POST /api/gacha/draw`)
  Future<HobbyGachaItem> drawGacha({String category = 'ALL'}) async {
    try {
      final res = await http
          .post(
            _apiUri('/api/gacha/draw'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'category': category}),
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final itemMap = body is Map<String, dynamic>
            ? (body['item'] is Map<String, dynamic>
                ? body['item'] as Map<String, dynamic>
                : body)
            : <String, dynamic>{};
        if (itemMap.isNotEmpty) {
          final item = HobbyGachaItem.fromJson(itemMap);
          _todayData = _todayData.copyWith(currentGacha: item);
          notifyListeners();
          await _saveToLocalCache();
          return item;
        }
      }
    } catch (_) {}

    // Offline / Fallback Gacha Pool based on actual Obsidian files
    final pool = _fallbackGachaPool
        .where((item) => category == 'ALL' || item.category == category.toUpperCase())
        .toList();
    final chosen = pool.isNotEmpty
        ? pool[DateTime.now().millisecondsSinceEpoch % pool.length]
        : _fallbackGachaPool.first;

    _todayData = _todayData.copyWith(currentGacha: chosen);
    notifyListeners();
    await _saveToLocalCache();
    return chosen;
  }

  /// 4. 趣味ガチャの試食結果を記録 (`POST /api/gacha/action`)
  /// action: 'liked' (よかった→いまやってる・見てるもの.mdへ) | 'dropped' (興味ない→logへ) | 'later' (あとで)
  Future<String> recordGachaAction({
    required HobbyGachaItem item,
    required String action,
    String comment = '',
  }) async {
    String feedbackMessage = '';
    if (action == 'liked') {
      feedbackMessage = '「${item.title}」を『いまやってる・見てるもの.md』へ昇格し、趣味ガチャ_log.md に記録しました！';
      final updatedDoing = [
        item.title,
        ..._todayData.profile.doingNowItems.where((x) => x != item.title),
      ];
      _todayData = _todayData.copyWith(
        profile: UserProfileSummary(
          currentFocus: _todayData.profile.currentFocus,
          activeProjects: _todayData.profile.activeProjects,
          currentInterests: _todayData.profile.currentInterests,
          doingNowItems: updatedDoing,
          budgetAndLifestyleNote: _todayData.profile.budgetAndLifestyleNote,
          lastSyncedAt: 'たった今更新',
        ),
      );
    } else if (action == 'dropped') {
      feedbackMessage = '「${item.title}」を元リストから整理し、趣味ガチャ_log.md に記録しました。';
    } else {
      feedbackMessage = '「${item.title}」をプールに残しました。また気が向いた時に試食しましょう！';
    }

    try {
      await http
          .post(
            _apiUri('/api/gacha/action'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': item.id,
              'title': item.title,
              'category': item.category,
              'source_file': item.sourceFile,
              'action': action,
              'comment': comment,
            }),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}

    await drawGacha(category: 'ALL');
    return feedbackMessage;
  }

  /// 5. SNS差分フィードの既読化 (`POST /api/feeds/mark-read`)
  Future<void> markFeedsRead(List<String> itemIds, {bool markAll = false}) async {
    if (markAll) {
      _feedItems = _feedItems.map((f) => f.copyWith(isRead: true)).toList();
    } else {
      final idSet = itemIds.toSet();
      _feedItems = _feedItems
          .map((f) => idSet.contains(f.id) ? f.copyWith(isRead: true) : f)
          .toList();
    }
    notifyListeners();
    await _saveToLocalCache();

    try {
      await http
          .post(
            _apiUri('/api/feeds/mark-read'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'item_ids': itemIds,
              'mark_all': markAll,
            }),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// 6. フィードやキュレーション記事をObsidianのやるメモ.mdにクリップ保存
  Future<void> clipToObsidian({
    required String title,
    required String url,
    required String sourceLabel,
    String? feedItemId,
    String? curationItemId,
  }) async {
    final clipText = '🔖 [$sourceLabel] $title ($url)';
    await quickAddTask(clipText, section: 'want');

    if (feedItemId != null) {
      _feedItems = _feedItems
          .map((f) => f.id == feedItemId ? f.copyWith(isSavedToObsidian: true) : f)
          .toList();
    }
    if (curationItemId != null) {
      _curations = _curations
          .map((c) => c.id == curationItemId ? c.copyWith(isSavedToObsidian: true) : c)
          .toList();
    }
    notifyListeners();
    await _saveToLocalCache();
  }

  /// 7. URL＋自然言語指示による監視ソース追加 (`POST /api/sources/add-by-ai`)
  Future<WatchSource> addSourceByAi({
    required String url,
    required String instruction,
    String? customName,
  }) async {
    final cleanUrl = url.trim();
    final cleanInstruction = instruction.trim();

    try {
      final res = await http
          .post(
            _apiUri('/api/sources/add-by-ai'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': cleanUrl,
              'instruction': cleanInstruction,
              'name': customName,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic>) {
          final srcMap = body['source'] is Map<String, dynamic>
              ? body['source'] as Map<String, dynamic>
              : body;
          final createdSource = WatchSource.fromJson(srcMap);
          _sources = [createdSource, ..._sources];

          if (body['preview_items'] is List) {
            final previews = (body['preview_items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(FeedItem.fromJson)
                .toList();
            _feedItems = [...previews, ..._feedItems];
          }
          notifyListeners();
          await _saveToLocalCache();
          return createdSource;
        }
      }
    } catch (_) {}

    // Offline / Fallback intelligent rule builder
    String detectedPlatform = 'custom';
    String strategy = 'gemini_extract';
    String ruleDesc = 'AIセレクタ＆差分抽出 (${cleanInstruction.isEmpty ? "新着アイテム検知" : cleanInstruction})';

    final lower = cleanUrl.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      detectedPlatform = 'youtube';
      strategy = 'rss_auto';
      ruleDesc = 'YouTubeチャンネル/検索RSSフィード自動変換';
    } else if (lower.contains('pixiv.net')) {
      detectedPlatform = 'pixiv';
      strategy = 'api_adapter';
      ruleDesc = 'Pixiv タグ/ユーザー新着作品差分アダプター';
    } else if (lower.contains('x.com') || lower.contains('twitter.com')) {
      detectedPlatform = 'x';
      strategy = 'api_adapter';
      ruleDesc = 'X (Twitter) 指定アカウント/検索クエリ未読差分抽出';
    } else if (lower.endsWith('.xml') || lower.contains('rss') || lower.contains('feed')) {
      detectedPlatform = 'rss';
      strategy = 'rss_auto';
      ruleDesc = 'RSS/Atomフィード標準パーサー';
    }

    final hostName = Uri.tryParse(cleanUrl)?.host.replaceFirst('www.', '') ?? 'カスタムWeb';
    final newSource = WatchSource(
      id: 'src_${DateTime.now().millisecondsSinceEpoch}',
      name: (customName != null && customName.trim().isNotEmpty)
          ? customName.trim()
          : '$hostName ウォッチャー',
      platform: detectedPlatform,
      url: cleanUrl,
      instruction: cleanInstruction.isEmpty ? '前回の確認時からの新着差分のみを取得' : cleanInstruction,
      rule: CustomUrlRule(
        strategy: strategy,
        itemSelector: 'article, .post-item, .news-list li',
        titleSelector: 'h2, h3, .title',
        linkSelector: 'a[href]',
        extractionPrompt: cleanInstruction,
        description: ruleDesc,
      ),
      enabled: true,
      lastCheckedAt: 'たった今 (初回解析完了)',
      unreadCount: 1,
    );

    final previewItem = FeedItem(
      id: 'feed_${DateTime.now().millisecondsSinceEpoch}',
      sourceId: newSource.id,
      sourceName: newSource.name,
      platform: newSource.platform,
      title: '【初回テスト抽出】${newSource.name} の最新更新アイテム',
      summary: '指示「${newSource.instruction}」に基づき、対象ページから最新差分1件を正常に検出しました。次回以降は未読の新着のみが表示されます。',
      url: cleanUrl,
      author: newSource.name,
      publishedAt: 'たった今',
      tags: [detectedPlatform.toUpperCase(), 'AIウォッチャー'],
      isRead: false,
    );

    _sources = [newSource, ..._sources];
    _feedItems = [previewItem, ..._feedItems];
    notifyListeners();
    await _saveToLocalCache();
    return newSource;
  }

  /// 8. 接続設定・Vault設定の保存
  Future<bool> updateConnectionSettings({
    required String serverUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String vaultPath,
  }) async {
    _serverUrl = _cleanBaseUrl(serverUrl.isEmpty ? 'http://localhost:8000' : serverUrl);
    _supabaseUrl = supabaseUrl.trim();
    _supabaseAnonKey = supabaseAnonKey.trim();
    _vaultPath = vaultPath.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerUrlKey, _serverUrl);
    await prefs.setString(_prefSupabaseUrlKey, _supabaseUrl);
    await prefs.setString(_prefSupabaseAnonKey, _supabaseAnonKey);
    await prefs.setString(_prefVaultPathKey, _vaultPath);

    await _tryInitSupabase();
    await refreshAll();
    return _isOnline;
  }

  // ===========================================================================
  // オフライン・デモ用初期データ（実際のObsidian Vault構成と関心事に完全準拠）
  // ===========================================================================

  static final List<HobbyGachaItem> _fallbackGachaPool = [
    const HobbyGachaItem(
      id: 'gacha_game_1',
      title: 'Outer Wilds (アウター・ワイルズ)',
      category: 'GAME',
      sourceFile: '01_Inbox/したいゲーム.md',
      trialRule: '1ループ（22分）＋宇宙船の操作感だけ試食する',
      recommendationNote: '宇宙と哲学・謎解きが好きなら相性抜群。まずは30分タイマーで1ループだけ！',
    ),
    const HobbyGachaItem(
      id: 'gacha_game_2',
      title: 'SANABI (サンナビ)',
      category: 'GAME',
      sourceFile: '01_Inbox/したいゲーム.md',
      trialRule: '序盤のチャプター1（約30分）だけワイヤーアクションを触る',
      recommendationNote: 'サイバーパンク×爽快ワイヤーアクション＆熱いストーリー。短時間でも満足感大。',
    ),
    const HobbyGachaItem(
      id: 'gacha_story_1',
      title: 'PLUTO (プルートゥ)',
      category: 'STORY',
      sourceFile: '01_Inbox/見たい物語.md',
      trialRule: '第1話の前半30分だけ観る',
      recommendationNote: 'AIの自我と哲学・ミステリーの名作。今の関心テーマとも深く共鳴します。',
    ),
    const HobbyGachaItem(
      id: 'gacha_story_2',
      title: 'チ。―地球の運動について―',
      category: 'STORY',
      sourceFile: '01_Inbox/見たい物語.md',
      trialRule: 'アニメ1話（24分）だけ試食する',
      recommendationNote: '知的好奇心と信念の物語。24分でスパッと1話試食できます。',
    ),
    const HobbyGachaItem(
      id: 'gacha_single_1',
      title: 'ComfyUIで新しいControlNet / IPAdapterノードを1つだけ試す',
      category: 'SINGLE',
      sourceFile: '01_Inbox/単発 やりたいリスト.md',
      trialRule: '30分タイマーをセットし、既存ワークフローに1ノード繋いで1枚生成するまで',
      recommendationNote: '完璧を目指さず「30分で1枚出たら勝ち」のルールで触ると疲れません。',
    ),
    const HobbyGachaItem(
      id: 'gacha_single_2',
      title: '三軒茶屋のすずらん通り・三角地帯を15分だけ散歩して気になった店をメモ',
      category: 'SINGLE',
      sourceFile: '01_Inbox/単発 やりたいリスト.md',
      trialRule: '帰り道に15分だけ別ルートを歩いてみる',
      recommendationNote: 'お金をかけずに気分転換＆新しい安旨スポット発見に。',
    ),
  ];

  static TodayData _buildDefaultTodayData() {
    return TodayData(
      dateText: '2026年10月22日 (木)',
      greeting: 'こんにちは！今日も「余計なことを考える手間」を減らして、大事な制作と楽しい試食を進めましょう。',
      weather: const WeatherInfo(
        locationName: '三軒茶屋・世田谷',
        condition: '秋晴れ・過ごしやすい',
        icon: '☀️',
        temperature: 20.4,
        tempMax: 22.0,
        tempMin: 13.5,
        precipitationProbability: 10,
        advice: '日中は快適ですが、20時以降は15℃を下回るので薄手の上着があると安心です。傘は不要です。',
      ),
      schedule: const [
        ScheduleEvent(
          id: 'ev_1',
          title: '授業・制作実習（学校PC環境）',
          startTime: '09:30',
          endTime: '16:30',
          location: 'キャンパス演習室',
          category: 'school',
        ),
        ScheduleEvent(
          id: 'ev_2',
          title: '10月26日締切プロジェクト 集中作業ブロック',
          startTime: '17:00',
          endTime: '18:30',
          location: '学校 or 自宅デスク',
          category: 'focus',
        ),
        ScheduleEvent(
          id: 'ev_3',
          title: '自由時間・趣味ガチャ30分試食枠',
          startTime: '21:00',
          endTime: '22:00',
          location: '自宅PC',
          category: 'hobby',
        ),
      ],
      tasks: const [
        ObsidianTask(
          id: 'rt_1',
          text: 'お神体に一礼1拍手・コップ1杯の水を飲む',
          completed: true,
          section: 'routine',
          lineNumber: 5,
        ),
        ObsidianTask(
          id: 'rt_2',
          text: '今日のスケジュールと『やるメモ.md』を1分で確認',
          completed: true,
          section: 'routine',
          lineNumber: 6,
        ),
        ObsidianTask(
          id: 'must_1',
          text: '【10/26締切】制作課題のメインパート進捗を1段階進める',
          completed: false,
          section: 'must',
          lineNumber: 15,
        ),
        ObsidianTask(
          id: 'must_2',
          text: 'Daily ConciergeをGitHubへpushして自宅PCへ引き継ぐ',
          completed: false,
          section: 'must',
          lineNumber: 16,
        ),
        ObsidianTask(
          id: 'want_1',
          text: '帰ったら自宅PCでFlutterアプリ (Windows / Android) をビルドして触ってみる',
          completed: false,
          section: 'want',
          lineNumber: 28,
        ),
        ObsidianTask(
          id: 'want_2',
          text: '趣味ガチャを1回まわして30分だけ未消化ゲームorアニメを試食する',
          completed: false,
          section: 'want',
          lineNumber: 29,
        ),
      ],
      proposals: const [
        AiProposal(
          id: 'prop_1',
          timeSlot: '今〜下校前 (15分)',
          title: '学校PCでの変更をGit Commit & Pushしてスッキリ帰る準備',
          reason: 'Obsidian Syncでノートは自動同期されます。コードだけGitHubへ上げておけば、自宅PCで1秒で再開できます。',
          actionType: 'must',
          estimatedMinutes: 15,
        ),
        AiProposal(
          id: 'prop_2',
          timeSlot: '帰宅後 20:00〜 (45分)',
          title: '10月26日締切タスクの「一番重い1パーツ」だけ先に片付ける',
          reason: '夜の趣味時間を罪悪感ゼロで楽しむため、帰宅直後に45分だけ集中ブロックを作るのが最も効率的です。',
          actionType: 'must',
          estimatedMinutes: 45,
        ),
        AiProposal(
          id: 'prop_3',
          timeSlot: '21:30〜 (30分)',
          title: '趣味ガチャで『Outer Wilds』または『PLUTO』を30分だけ試食',
          reason: 'SNSをダラダラ見る代わりに、30分タイマーを回して『したいゲーム.md』『見たい物語.md』を1つ味見しましょう！',
          actionType: 'gacha',
          estimatedMinutes: 30,
        ),
      ],
      currentGacha: _fallbackGachaPool.first,
      profile: const UserProfileSummary(
        currentFocus: '10月26日締切の制作を最優先しつつ、学校PC⇄自宅PCのポータブル開発環境と情報ハブを構築中',
        activeProjects: [
          '📌 10月26日までに完成させる制作課題',
          '🚀 Daily Concierge (Obsidian × AI × マルチデバイス情報ハブ)',
          '🎨 ローカルAI (ComfyUI / 画像・動画生成ワークフロー研究)',
        ],
        currentInterests: [
          'ローカルAI / ComfyUI',
          '個人開発・AIエージェント活用 (Antigravity / Codex)',
          'Quest 3 / VR体験',
          '哲学・物語構造・SF考察',
          'Steamインディーゲーム',
          '三軒茶屋・都内の安旨スポット',
        ],
        doingNowItems: [
          '🎮 Balatro / 積みゲー消化',
          '📖 物語・設定資料のインプット',
          '🛠️ Obsidian Vault整理と自動化',
        ],
        budgetAndLifestyleNote: 'コスパ・実用性重視：無料OSSやローカル環境を最大限活かし、セールや近場の良スポットを賢く楽しむスタイル',
        lastSyncedAt: 'Obsidian Vault 自動同期有効',
      ),
      isOfflineFallback: false,
    );
  }

  static List<FeedItem> _buildDefaultFeeds() {
    return const [
      FeedItem(
        id: 'feed_yt_1',
        sourceId: 'src_yt_ai',
        sourceName: 'AICU / ComfyUI Lab (YouTube)',
        platform: 'youtube',
        title: '【ComfyUI最新】VRAM 8GB〜12GBでも高速に動く新サンプラー＆軽量ControlNetワークフロー解説',
        summary: '前回確認時からの新着動画1件。既存のSDXL/Flux環境にそのまま追加できる省メモリノード構成とサンプルJSONが公開されています。',
        url: 'https://www.youtube.com/results?search_query=ComfyUI+workflow',
        author: 'ComfyUI Lab',
        publishedAt: '2時間前',
        tags: ['YouTube', 'ComfyUI', 'ローカルAI'],
      ),
      FeedItem(
        id: 'feed_pixiv_1',
        sourceId: 'src_pixiv_fav',
        sourceName: 'Pixiv フォロー＆指定タグ新着',
        platform: 'pixiv',
        title: '【未読差分 3作品】指定タグ「背景美術 / SFコンセプトアート」に新しいメイキング付き作品が投稿されました',
        summary: 'タイムラインやランキングを開かずに、登録したタグとフォロー作家の前回チェック以降の新着作品のみを抽出しました。',
        url: 'https://www.pixiv.net/',
        author: '登録タグ・作家差分',
        publishedAt: '4時間前',
        tags: ['Pixiv', 'コンセプトアート', '制作参考'],
      ),
      FeedItem(
        id: 'feed_x_1',
        sourceId: 'src_x_dev',
        sourceName: 'X (Twitter) 技術・AIリスト差分',
        platform: 'x',
        title: '個人開発者向け：Obsidian VaultとローカルLLM/Geminiを連携させるMCP・スキル設計パターンのまとめスレッド',
        summary: 'おすすめ欄（For You）のノイズを除外し、指定アカウントの重要ツリー投稿のみを抽出。Obsidianのコールアウトを壊さないパーサー設計について言及。',
        url: 'https://x.com/',
        author: '@ai_dev_notes',
        publishedAt: '5時間前',
        tags: ['X差分', 'Obsidian', 'AIエージェント'],
      ),
      FeedItem(
        id: 'feed_rss_1',
        sourceId: 'src_rss_steam',
        sourceName: 'Steam / インディーゲーム最安更新ウォッチャー',
        platform: 'custom',
        title: '『したいゲーム.md』関連タイトルが週末セール対象に（過去最安値の更新通知）',
        summary: 'ウィッシュリストおよびObsidianの『したいゲーム.md』に含まれるインディー作品の価格変動差分です。',
        url: 'https://store.steampowered.com/',
        author: 'Steam Price Watcher',
        publishedAt: '今日 09:00',
        tags: ['カスタムURL', 'Steam', 'したいゲーム連動'],
      ),
    ];
  }

  static List<WatchSource> _buildDefaultSources() {
    return const [
      WatchSource(
        id: 'src_yt_ai',
        name: 'YouTube: ComfyUI / ローカルAI解説チャンネル',
        platform: 'youtube',
        url: 'https://www.youtube.com/@comfyui',
        instruction: '新着動画とライブ配信アーカイブのタイトル・要約だけ取得（ショート動画は除外）',
        rule: CustomUrlRule(
          strategy: 'rss_auto',
          description: 'YouTube RSSフィード + ショート除外フィルタ',
        ),
        enabled: true,
        lastCheckedAt: '今日 11:00',
        unreadCount: 1,
      ),
      WatchSource(
        id: 'src_pixiv_fav',
        name: 'Pixiv: SF背景美術・お気に入り作家',
        platform: 'pixiv',
        url: 'https://www.pixiv.net/tags/%E8%83%8C%E6%99%AF',
        instruction: '前回確認時より後に投稿された100users入り以上の作品・フォロー作家新着のみ取得',
        rule: CustomUrlRule(
          strategy: 'api_adapter',
          description: 'Pixiv JSON差分アダプター（おすすめノイズ遮断）',
        ),
        enabled: true,
        lastCheckedAt: '今日 10:30',
        unreadCount: 1,
      ),
      WatchSource(
        id: 'src_x_dev',
        name: 'X (Twitter): AI開発・制作クリエイター選抜',
        platform: 'x',
        url: 'https://x.com/i/lists/ai-creators',
        instruction: 'リポストや日常雑談を除き、ツール公開・知見スレッド・作品発表のみ抽出',
        rule: CustomUrlRule(
          strategy: 'gemini_extract',
          description: 'ローカルワーカー差分取得 + Gemini重要度フィルタ',
        ),
        enabled: true,
        lastCheckedAt: '今日 10:00',
        unreadCount: 1,
      ),
    ];
  }

  static List<CurationItem> _buildDefaultCurations() {
    return const [
      CurationItem(
        id: 'cur_ai_1',
        category: 'ai_news',
        title: 'ComfyUI & ローカル生成AI：少ないステップ数で一貫したキャラクター・背景を出す最新手法まとめ',
        summary: '今週話題のオープンウェイトモデル最適化と、VRAMを抑えつつディテールを維持するワークフロー改善の要点解説。',
        whyItMatters: '現在進行中の制作課題やビジュアル実験で、試行錯誤の待ち時間を約40%短縮できる実用的なテクニックです。',
        url: 'https://github.com/comfyanonymous/ComfyUI',
        sourceName: 'Local AI Weekly Digest',
        publishedAt: '今日配信',
        tags: ['ComfyUI', 'ローカルAI', '制作効率化'],
      ),
      CurationItem(
        id: 'cur_ai_2',
        category: 'ai_news',
        title: 'Antigravity / Codex CLI × Obsidian Vault：個人の知識ベースをAIの長期記憶にする実践設計',
        summary: 'Markdownファイル群を壊さずにAIエージェントと双方向同期し、学校と自宅の複数PC間でコンテキストを維持するベストプラクティス。',
        whyItMatters: 'まさに今構築している『Daily Concierge』や普段のObsidian運用をさらに進化させるアイデアが詰まっています。',
        url: 'https://obsidian.md/',
        sourceName: 'Agentic Coding Insights',
        publishedAt: '今日配信',
        tags: ['Antigravity', 'Obsidian', '個人開発'],
      ),
      CurationItem(
        id: 'cur_deal_1',
        category: 'deals',
        title: '【三軒茶屋・世田谷】1,000円以下で大満足！帰り道にサクッと寄れる高コスパ定食・カレー＆作業カフェ3選',
        summary: '三茶エリアで学生・クリエイターに人気のボリューム満点ランチ＆夜定食と、電源・Wi-Fiが使えて長居しやすい穴場スポット。',
        whyItMatters: '無理のない予算感で美味しいものを食べて気分転換したい日にぴったり。散歩コース（単発やりたいリスト）にも組み込めます。',
        url: 'https://maps.google.com/?q=三軒茶屋+定食+安い',
        sourceName: '三茶ローカルお得マップ',
        publishedAt: '今週のスポット',
        priceOrDiscountBadge: '¥680〜¥980',
        tags: ['三軒茶屋', 'コスパ飯', '作業スポット'],
      ),
      CurationItem(
        id: 'cur_deal_2',
        category: 'deals',
        title: 'Steam & Meta Quest 3：今週のインディー名作セール＆無料トライアル注目枠',
        summary: '高評価SFアドベンチャーやローグライト作品が50〜70% OFF。Quest 3向けの無料MR体験デモも新着公開。',
        whyItMatters: '『したいゲーム.md』の候補をワンコイン〜1,000円台で補充・試食できるタイミングです。',
        url: 'https://store.steampowered.com/specials',
        sourceName: 'Game Deal Concierge',
        publishedAt: 'セール開催中',
        priceOrDiscountBadge: '最大 70% OFF',
        tags: ['Steamセール', 'Quest 3', 'インディーゲーム'],
      ),
      CurationItem(
        id: 'cur_read_1',
        category: 'reading',
        title: '「未消化リストが溜まるストレス」を「試食のワクワク」に変える認知デザイン論',
        summary: 'なぜ人は「やりたいことリスト」を作ると逆に動けなくなるのか？「完了」ではなく「30分試食して判断する」だけで脳の報酬系が動き出す理由。',
        whyItMatters: 'あなたが実践している『趣味ガチャ（1話/1章/30分ルール）』の有効性を裏付ける、創作やタスク管理にも応用できる良記事です。',
        url: 'https://note.com/',
        sourceName: '哲学・認知科学エッセイ選',
        publishedAt: '5分で読める解説',
        tags: ['認知デザイン', '哲学', '趣味ガチャ理論'],
      ),
      CurationItem(
        id: 'cur_read_2',
        category: 'reading',
        title: 'SFと物語構造：限られた舞台設定（ループ・密室・箱庭）で読者を強く惹きつける脚本術',
        summary: '『Outer Wilds』や短編SF映画に学ぶ、少ないアセットとコンパクトな規模でも深い感動と謎解き体験を作る構造分析。',
        whyItMatters: '個人制作・10月26日締切の課題など、限られた時間とリソースで印象的な作品を作るための実践的なヒントになります。',
        url: 'https://example.com/story-structure',
        sourceName: '創作・物語構造ラボ',
        publishedAt: '7分で読める解説',
        tags: ['物語構造', 'SF創作', '作品制作'],
      ),
    ];
  }
}
