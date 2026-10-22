import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../services/api_service.dart';

class SnsFeedScreen extends StatefulWidget {
  const SnsFeedScreen({super.key});

  @override
  State<SnsFeedScreen> createState() => _SnsFeedScreenState();
}

class _SnsFeedScreenState extends State<SnsFeedScreen> {
  String _selectedPlatform = 'all';
  bool _showReadItems = false;

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _platformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Colors.redAccent;
      case 'pixiv':
        return Colors.lightBlueAccent;
      case 'x':
      case 'twitter':
        return Colors.purpleAccent;
      case 'rss':
        return Colors.orangeAccent;
      default:
        return Colors.tealAccent;
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_outline;
      case 'pixiv':
        return Icons.palette_outlined;
      case 'x':
      case 'twitter':
        return Icons.alternate_email;
      case 'rss':
        return Icons.rss_feed;
      default:
        return Icons.public;
    }
  }

  void _showPreviewModal(BuildContext context, ConciergeState state, FeedItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_platformIcon(item.platform), color: _platformColor(item.platform), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.sourceName} • ${item.publishedAt}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.summary.isNotEmpty
                        ? item.summary
                        : 'このアイテムの詳細プレビューです。タイムラインのおすすめ欄や広告ノイズを介さず、更新内容の要点だけを確認できます。',
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ),
                const SizedBox(height: 12),
                if (item.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.tags
                        .map(
                          (t) => Chip(
                            label: Text('#$t', style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        state.markFeedsRead([item.id]);
                        Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.done, size: 18),
                      label: const Text('既読にして閉じる'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await state.clipToObsidian(
                          title: item.title,
                          url: item.url,
                          sourceLabel: item.platformLabel,
                          feedItemId: item.id,
                        );
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔖 Obsidian『やるメモ.md』にクリップ保存しました'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('Obsidianへクリップ'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openExternalUrl(item.url),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('元ページを開く'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConciergeState>();
    final allItems = state.feedItems;

    final filtered = allItems.where((item) {
      if (!_showReadItems && item.isRead) return false;
      if (_selectedPlatform != 'all' && item.platform.toLowerCase() != _selectedPlatform) {
        return false;
      }
      return true;
    }).toList();

    final unreadCount = state.unreadFeedItems.length;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox_outlined, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'SNS・Web 差分フィード (未読 $unreadCount 件)',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'タイムラインやおすすめ欄を開かず、指定アカウント・タグ・URLの前回からの差分だけを確認',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilterChip(
                            label: const Text('既読も表示', style: TextStyle(fontSize: 12)),
                            selected: _showReadItems,
                            onSelected: (val) {
                              setState(() {
                                _showReadItems = val;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: filtered.isEmpty
                                ? null
                                : () {
                                    state.markFeedsRead(
                                      filtered.map((e) => e.id).toList(),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✨ 表示中の差分フィードをすべて既読にしました（Inbox Zero!）'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.done_all, size: 16),
                            label: const Text('すべて既読にする', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPlatformChip('all', 'すべて'),
                        const SizedBox(width: 8),
                        _buildPlatformChip('youtube', 'YouTube'),
                        const SizedBox(width: 8),
                        _buildPlatformChip('pixiv', 'Pixiv'),
                        const SizedBox(width: 8),
                        _buildPlatformChip('x', 'X (Twitter)'),
                        const SizedBox(width: 8),
                        _buildPlatformChip('custom', 'カスタムURL / RSS'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 56, color: Colors.tealAccent),
                      const SizedBox(height: 12),
                      const Text(
                        '未読の新着差分はありません（Inbox Zero!）',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '時間を奪われることなくチェック完了です。趣味ガチャや制作に時間を使いましょう！',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showReadItems = true;
                          });
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('既読アイテムを表示する'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return Dismissible(
                    key: ValueKey('feed_${item.id}'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) {
                      state.markFeedsRead([item.id]);
                    },
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check, color: Colors.white),
                          SizedBox(width: 8),
                          Text('既読にする', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('既読にする', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.check, color: Colors.white),
                        ],
                      ),
                    ),
                    child: _buildFeedItemCard(context, state, item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlatformChip(String value, String label) {
    final isSelected = _selectedPlatform == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedPlatform = value;
        });
      },
    );
  }

  Widget _buildFeedItemCard(BuildContext context, ConciergeState state, FeedItem item) {
    final cs = Theme.of(context).colorScheme;
    final pColor = _platformColor(item.platform);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.isRead
              ? cs.outlineVariant.withOpacity(0.3)
              : pColor.withOpacity(0.45),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showPreviewModal(context, state, item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_platformIcon(item.platform), size: 13, color: pColor),
                        const SizedBox(width: 4),
                        Text(
                          item.platformLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: pColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.sourceName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    item.publishedAt,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: item.isRead ? Colors.grey : null,
                ),
              ),
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    children: item.tags
                        .map(
                          (t) => Text(
                            '#$t',
                            style: TextStyle(fontSize: 11, color: cs.primary),
                          ),
                        )
                        .toList(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showPreviewModal(context, state, item),
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('アプリ内プレビュー', style: TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        tooltip: 'Obsidian (やるメモ.md) へクリップ',
                        onPressed: () async {
                          await state.clipToObsidian(
                            title: item.title,
                            url: item.url,
                            sourceLabel: item.platformLabel,
                            feedItemId: item.id,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔖 Obsidian『やるメモ.md』にクリップ保存しました'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: Icon(
                          item.isSavedToObsidian ? Icons.bookmark : Icons.bookmark_add_outlined,
                          size: 18,
                          color: item.isSavedToObsidian ? Colors.amberAccent : null,
                        ),
                      ),
                      if (!item.isRead)
                        IconButton(
                          tooltip: '既読にする',
                          onPressed: () => state.markFeedsRead([item.id]),
                          icon: const Icon(Icons.check_circle_outline, size: 19, color: Colors.tealAccent),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
