import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/curation_item.dart';
import '../services/api_service.dart';

class CurationScreen extends StatefulWidget {
  const CurationScreen({super.key});

  @override
  State<CurationScreen> createState() => _CurationScreenState();
}

class _CurationScreenState extends State<CurationScreen> {
  String _selectedCategory = 'all';

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'ai_news':
        return Colors.cyanAccent;
      case 'deals':
        return Colors.amberAccent;
      case 'reading':
        return Colors.purpleAccent;
      default:
        return Colors.tealAccent;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'ai_news':
        return Icons.memory;
      case 'deals':
        return Icons.local_offer_outlined;
      case 'reading':
        return Icons.menu_book_outlined;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConciergeState>();
    final allItems = state.curations;

    final filtered = allItems.where((item) {
      if (_selectedCategory == 'all') return true;
      return item.category == _selectedCategory;
    }).toList();

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryFilter('all', '✨ すべて'),
                      const SizedBox(width: 8),
                      _buildCategoryFilter('ai_news', '🤖 ローカルAI・開発ツール'),
                      const SizedBox(width: 8),
                      _buildCategoryFilter('deals', '🏷️ Steam・Quest 3・三茶お得情報'),
                      const SizedBox(width: 8),
                      _buildCategoryFilter('reading', '📚 良記事・哲学・創作読み物'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isWide)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: filtered
                        .map(
                          (item) => SizedBox(
                            width: (constraints.maxWidth - 48) / 2,
                            child: _buildCurationCard(context, state, item),
                          ),
                        )
                        .toList(),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: filtered
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildCurationCard(context, state, item),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_stories_outlined, size: 20, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AIニュース・お得情報・良記事キュレーション',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Obsidian Vault内の「今の関心事（ComfyUI・個人開発・Quest 3・Steam・三軒茶屋コスパスポット・創作論）」に合わせて、今日知っておくと得する情報だけを解説付きで厳選しています。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(String value, String label) {
    final selected = _selectedCategory == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedCategory = value;
        });
      },
    );
  }

  Widget _buildCurationCard(
    BuildContext context,
    ConciergeState state,
    CurationItem item,
  ) {
    final cs = Theme.of(context).colorScheme;
    final catColor = _categoryColor(item.category);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: catColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_categoryIcon(item.category), size: 16, color: catColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.categoryLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: catColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.priceOrDiscountBadge != null &&
                    item.priceOrDiscountBadge!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amberAccent),
                    ),
                    child: Text(
                      item.priceOrDiscountBadge!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.summary,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withOpacity(0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '今のあなたへの関連ポイント: ${item.whyItMatters}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('#$tag', style: const TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item.sourceName} • ${item.publishedAt}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await state.clipToObsidian(
                          title: item.title,
                          url: item.url,
                          sourceLabel: 'キュレーション',
                          curationItemId: item.id,
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
                        size: 16,
                      ),
                      label: Text(
                        item.isSavedToObsidian ? '保存済' : 'Obsidian保存',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openExternalUrl(item.url),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('開く', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
