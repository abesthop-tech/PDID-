import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_item.dart';
import '../services/api_service.dart';

class SourcesSettingsScreen extends StatefulWidget {
  const SourcesSettingsScreen({super.key});

  @override
  State<SourcesSettingsScreen> createState() => _SourcesSettingsScreenState();
}

class _SourcesSettingsScreenState extends State<SourcesSettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();
  final TextEditingController _sourceNameController = TextEditingController();

  late TextEditingController _serverUrlController;
  late TextEditingController _supabaseUrlController;
  late TextEditingController _supabaseAnonKeyController;
  late TextEditingController _vaultPathController;

  bool _isAddingSource = false;
  bool _isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<ConciergeState>();
    _serverUrlController = TextEditingController(text: state.serverUrl);
    _supabaseUrlController = TextEditingController(text: state.supabaseUrl);
    _supabaseAnonKeyController = TextEditingController(text: state.supabaseAnonKey);
    _vaultPathController = TextEditingController(text: state.vaultPath);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _instructionController.dispose();
    _sourceNameController.dispose();
    _serverUrlController.dispose();
    _supabaseUrlController.dispose();
    _supabaseAnonKeyController.dispose();
    _vaultPathController.dispose();
    super.dispose();
  }

  Future<void> _handleAddSourceByAi(ConciergeState state) async {
    final url = _urlController.text.trim();
    final instruction = _instructionController.text.trim();
    final name = _sourceNameController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('監視したいページのURLを入力してください'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isAddingSource = true;
    });

    final created = await state.addSourceByAi(
      url: url,
      instruction: instruction.isEmpty ? '前回確認時からの新着アイテムのみを抽出して' : instruction,
      customName: name.isEmpty ? null : name,
    );

    if (!mounted) return;
    setState(() {
      _isAddingSource = false;
      _urlController.clear();
      _instructionController.clear();
      _sourceNameController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ 監視ソース「${created.name}」を追加し、初回差分プレビューをフィードに登録しました！'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSaveSettings(ConciergeState state) async {
    setState(() {
      _isSavingSettings = true;
    });

    final online = await state.updateConnectionSettings(
      serverUrl: _serverUrlController.text,
      supabaseUrl: _supabaseUrlController.text,
      supabaseAnonKey: _supabaseAnonKeyController.text,
      vaultPath: _vaultPathController.text,
    );

    if (!mounted) return;
    setState(() {
      _isSavingSettings = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          online
              ? '🌐 設定を保存し、バックエンドサーバー (${state.serverUrl}) と正常に同期しました！'
              : '💾 設定を保存しました（現在サーバー未接続のためローカルキャッシュ＆デモモードで動作中）',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConciergeState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildAddSourceByAiCard(context, state),
                          const SizedBox(height: 16),
                          _buildRegisteredSourcesCard(context, state),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _buildConnectionAndVaultSettingsCard(context, state),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAddSourceByAiCard(context, state),
                    const SizedBox(height: 16),
                    _buildRegisteredSourcesCard(context, state),
                    const SizedBox(height: 16),
                    _buildConnectionAndVaultSettingsCard(context, state),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddSourceByAiCard(BuildContext context, ConciergeState state) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.primary.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_link, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '＋ AI自然言語ウォッチャー追加 (YouTube / Pixiv / X / 任意Webサイト)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'URLを貼って「このページの〜の情報を取って」と指示するだけで、RSS自動検出・CSSセレクタ生成・Gemini抽出ルールを自動構成します。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '監視したいURL (必須)',
                hintText: 'https://www.youtube.com/@... / https://www.pixiv.net/tags/... / 公式サイトURL',
                prefixIcon: const Icon(Icons.link),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _instructionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '自然言語での抽出指示 („どんな差分だけ欲しいか”)',
                hintText: '例: 「ショート動画を除いた新着解説動画だけ取って」「セール割引率50%以上の新着だけ教えて」',
                prefixIcon: const Icon(Icons.auto_fix_high_outlined),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sourceNameController,
                    decoration: InputDecoration(
                      labelText: '表示名 (任意・空欄なら自動命名)',
                      hintText: '例: ComfyUI公式リリース監視',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isAddingSource ? null : () => _handleAddSourceByAi(state),
                  icon: _isAddingSource
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt),
                  label: Text(_isAddingSource ? '解析中...' : 'AIでルール生成＆追加'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.smart_display_outlined, size: 15),
                  label: const Text('例: YouTubeチャンネル', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _urlController.text = 'https://www.youtube.com/@comfyui';
                    _instructionController.text = 'ショート動画を除き、新着の長尺解説動画だけ差分取得して';
                    _sourceNameController.text = 'YouTube: ComfyUI解説';
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.palette_outlined, size: 15),
                  label: const Text('例: Pixivタグ新着', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _urlController.text = 'https://www.pixiv.net/tags/SF%E8%83%8C%E6%99%AF';
                    _instructionController.text = '前回チェック時以降に投稿されたブックマーク数が高い作品のみ取得';
                    _sourceNameController.text = 'Pixiv: SF背景タグ差分';
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.public, size: 15),
                  label: const Text('例: イベント・特設サイト', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _urlController.text = 'https://store.steampowered.com/specials';
                    _instructionController.text = '『したいゲーム.md』のジャンルに合う最安更新タイトルだけ抽出して';
                    _sourceNameController.text = 'Steam特選セール監視';
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisteredSourcesCard(BuildContext context, ConciergeState state) {
    final cs = Theme.of(context).colorScheme;
    final sources = state.sources;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '登録済み監視ソース一覧 (${sources.length}件)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sources.map((src) => _buildSourceItem(context, src)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceItem(BuildContext context, WatchSource src) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  src.platform.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  src.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              Text(
                '最終確認: ${src.lastCheckedAt}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            src.url,
            style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '🎯 抽出指示: ${src.instruction}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '⚙️ 適用ルール: [${src.rule.strategy}] ${src.rule.description}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionAndVaultSettingsCard(BuildContext context, ConciergeState state) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_ethernet, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '接続先サーバー ＆ Supabase / Obsidian Vault 設定',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: state.isOnline
                    ? Colors.teal.withOpacity(0.15)
                    : Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    state.isOnline ? Icons.check_circle : Icons.info_outline,
                    size: 18,
                    color: state.isOnline ? Colors.tealAccent : Colors.amberAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.statusMessage,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'バックエンドAPI URL (PC起動時)',
                hintText: 'http://localhost:8000 または http://192.168.1.x:8000',
                helperText: 'Windowsアプリなら http://localhost:8000、同一Wi-FiのAndroid実機ならPCのLAN IPを指定',
                prefixIcon: const Icon(Icons.dns_outlined),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vaultPathController,
              decoration: InputDecoration(
                labelText: 'Obsidian Vault パス (学校PC ⇄ 自宅PC)',
                hintText: r'C:\Users\<User>\Documents\obs',
                helperText: '学校PCのリダイレクトパスと自宅PCのObsidian Syncフォルダを自動/手動切り替え',
                prefixIcon: const Icon(Icons.folder_special_outlined),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supabaseUrlController,
              decoration: InputDecoration(
                labelText: 'Supabase Project URL (任意・外出先クラウド同期用)',
                hintText: 'https://xxxx.supabase.co',
                prefixIcon: const Icon(Icons.cloud_outlined),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supabaseAnonKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Supabase Anon Key (任意)',
                hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI...',
                prefixIcon: const Icon(Icons.key_outlined),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _isSavingSettings ? null : () => _handleSaveSettings(state),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSavingSettings ? '接続確認中...' : '設定を保存＆接続テスト'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _serverUrlController.text = 'http://localhost:8000';
                  },
                  icon: const Icon(Icons.desktop_windows_outlined, size: 16),
                  label: const Text('ローカルPC既定値に戻す', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
