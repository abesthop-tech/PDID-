import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/today_data.dart';
import '../services/api_service.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final TextEditingController _quickMemoController = TextEditingController();
  String _selectedMemoSection = 'auto';

  // 30分趣味ガチャ試食タイマー用ステート
  Timer? _gachaTimer;
  int _remainingSeconds = 30 * 60;
  bool _isTimerRunning = false;
  String _selectedGachaCategory = 'ALL';

  @override
  void dispose() {
    _gachaTimer?.cancel();
    _quickMemoController.dispose();
    super.dispose();
  }

  void _toggleGachaTimer() {
    if (_isTimerRunning) {
      _gachaTimer?.cancel();
      setState(() {
        _isTimerRunning = false;
      });
      return;
    }

    setState(() {
      _isTimerRunning = true;
    });

    _gachaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isTimerRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏰ 30分試食タイマー完了！「よかった」「興味ない」「あとで」から結果を記録しましょう。'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _remainingSeconds -= 1;
        });
      }
    });
  }

  void _resetGachaTimer() {
    _gachaTimer?.cancel();
    setState(() {
      _isTimerRunning = false;
      _remainingSeconds = 30 * 60;
    });
  }

  String _formatTimer(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submitQuickMemo(ConciergeState state) async {
    final text = _quickMemoController.text.trim();
    if (text.isEmpty) return;

    _quickMemoController.clear();
    await state.quickAddTask(text, section: _selectedMemoSection);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📝 『やるメモ.md』に「$text」を追記しました'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConciergeState>();
    final data = state.todayData;

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
                _buildHeaderBanner(context, state, data),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左カラム: 今日の天気・予定・やるメモ双方向チェックリスト
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildWeatherAndScheduleRow(context, data, isWide: true),
                            const SizedBox(height: 16),
                            _buildQuickMemoCard(context, state),
                            const SizedBox(height: 16),
                            _buildYaruMemoChecklistCard(context, state, data),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 右カラム: AIコンシェルジュ提案・趣味ガチャ30分タイマー・今の私プロファイル
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAiProposalsCard(context, data),
                            const SizedBox(height: 16),
                            _buildHobbyGachaCard(context, state, data),
                            const SizedBox(height: 16),
                            _buildUserProfileCard(context, data),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWeatherAndScheduleRow(context, data, isWide: false),
                      const SizedBox(height: 16),
                      _buildAiProposalsCard(context, data),
                      const SizedBox(height: 16),
                      _buildQuickMemoCard(context, state),
                      const SizedBox(height: 16),
                      _buildYaruMemoChecklistCard(context, state, data),
                      const SizedBox(height: 16),
                      _buildHobbyGachaCard(context, state, data),
                      const SizedBox(height: 16),
                      _buildUserProfileCard(context, data),
                    ],
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderBanner(
    BuildContext context,
    ConciergeState state,
    TodayData data,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withOpacity(0.65),
            cs.secondaryContainer.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    data.dateText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: state.isOnline
                      ? Colors.teal.withOpacity(0.25)
                      : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: state.isOnline ? Colors.tealAccent : Colors.amberAccent,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state.isOnline ? Icons.cloud_done : Icons.offline_bolt,
                      size: 14,
                      color: state.isOnline ? Colors.tealAccent : Colors.amberAccent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        state.statusMessage,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.greeting,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.9),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherAndScheduleRow(
    BuildContext context,
    TodayData data, {
    required bool isWide,
  }) {
    final weatherCard = _buildWeatherCard(context, data.weather);
    final scheduleCard = _buildScheduleCard(context, data.schedule);

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: weatherCard),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: scheduleCard),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        weatherCard,
        const SizedBox(height: 12),
        scheduleCard,
      ],
    );
  }

  Widget _buildWeatherCard(BuildContext context, WeatherInfo weather) {
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
                Text(weather.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weather.locationName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '${weather.condition}  ${weather.temperature.toStringAsFixed(1)}°C',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '最高 ${weather.tempMax.toStringAsFixed(0)}°C / 最低 ${weather.tempMin.toStringAsFixed(0)}°C',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '☔ 降水確率 ${weather.precipitationProbability}%',
                  style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_outlined, size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      weather.advice,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(BuildContext context, List<ScheduleEvent> schedule) {
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
                Icon(Icons.event_note, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  '今日の予定 (Google Calendar)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (schedule.isEmpty)
              const Text(
                '今日の登録済み予定はありません（自由時間！）',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            else
              ...schedule.map(
                (ev) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ev.endTime.isNotEmpty
                              ? '${ev.startTime}-${ev.endTime}'
                              : ev.startTime,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (ev.location.isNotEmpty)
                              Text(
                                '📍 ${ev.location}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMemoCard(BuildContext context, ConciergeState state) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.primary.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '『やるメモ.md』クイック短文メモ追記（AI自動セクション振り分け）',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickMemoController,
                    onSubmitted: (_) => _submitQuickMemo(state),
                    decoration: InputDecoration(
                      hintText: '例: 帰ったらComfyUIのノード試す / 10/26課題のラフ出力...',
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMemoSection,
                    borderRadius: BorderRadius.circular(10),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('🤖 AI自動', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'must', child: Text('🔥 今日Must', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'want', child: Text('✨ 帰ったらWant', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'routine', child: Text('🌅 朝ルーチン', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedMemoSection = val;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => _submitQuickMemo(state),
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('追記'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYaruMemoChecklistCard(
    BuildContext context,
    ConciergeState state,
    TodayData data,
  ) {
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
                Icon(Icons.check_circle_outline, size: 19, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Obsidian『01_Inbox/やるメモ.md』双方向チェックリスト',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'チェックするとVault内のやるメモ.mdの該当行（- [ ] ⇄ - [x]）へ安全に同期されます',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const Divider(height: 22),
            _buildTaskSection(
              context,
              state,
              title: '🌅 朝ルーチン',
              tasks: data.routineTasks,
              badgeColor: Colors.orangeAccent,
            ),
            const SizedBox(height: 12),
            _buildTaskSection(
              context,
              state,
              title: '🔥 今日やること (Must / 締切優先)',
              tasks: data.mustTasks,
              badgeColor: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            _buildTaskSection(
              context,
              state,
              title: '✨ 帰ったら・やりたいこと (Want / メモ)',
              tasks: data.wantTasks,
              badgeColor: Colors.tealAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSection(
    BuildContext context,
    ConciergeState state, {
    required String title,
    required List<ObsidianTask> tasks,
    required Color badgeColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '$title (${tasks.where((t) => t.completed).length}/${tasks.length})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 4),
            child: Text('項目なし', style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          ...tasks.map(
            (task) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => state.toggleTask(task),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: task.completed,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => state.toggleTask(task),
                    ),
                    Expanded(
                      child: Text(
                        task.text,
                        style: TextStyle(
                          fontSize: 13,
                          decoration: task.completed ? TextDecoration.lineThrough : null,
                          color: task.completed ? Colors.grey : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAiProposalsCard(BuildContext context, TodayData data) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.primary.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AIコンシェルジュからの「今日なにする？」行動提案',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...data.proposals.map(
              (prop) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            prop.timeSlot,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '目安 ${prop.estimatedMinutes}分',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      prop.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prop.reason,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHobbyGachaCard(
    BuildContext context,
    ConciergeState state,
    TodayData data,
  ) {
    final cs = Theme.of(context).colorScheme;
    final gacha = data.currentGacha;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.purpleAccent.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.casino_outlined, color: Colors.purpleAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '🎲 趣味ガチャ ＆ 30分試食タイマー',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL', label: Text('全部', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'GAME', label: Text('ゲーム', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'STORY', label: Text('物語', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'SINGLE', label: Text('単発', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_selectedGachaCategory},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (selection) {
                    final cat = selection.first;
                    setState(() {
                      _selectedGachaCategory = cat;
                    });
                    state.drawGacha(category: cat);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (gacha != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            gacha.categoryLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _resetGachaTimer();
                            state.drawGacha(category: _selectedGachaCategory);
                          },
                          icon: const Icon(Icons.refresh, size: 15),
                          label: const Text('引き直す', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Text(
                      gacha.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '🎯 試食ルール: ${gacha.trialRule}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    if (gacha.recommendationNote != null &&
                        gacha.recommendationNote!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        gacha.recommendationNote!,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 30分カウントダウンタイマーバー
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 20, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimer(_remainingSeconds),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _toggleGachaTimer,
                      icon: Icon(_isTimerRunning ? Icons.pause : Icons.play_arrow, size: 16),
                      label: Text(_isTimerRunning ? '一時停止' : '30分試食開始'),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'タイマーリセット',
                      onPressed: _resetGachaTimer,
                      icon: const Icon(Icons.replay, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '試食後の判定（Obsidian『いまやってる・見てるもの.md』『趣味ガチャ_log.md』へ自動反映）:',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      _resetGachaTimer();
                      final msg = await state.recordGachaAction(
                        item: gacha,
                        action: 'liked',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                    label: const Text('よかった (進行中へ昇格)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      _resetGachaTimer();
                      final msg = await state.recordGachaAction(
                        item: gacha,
                        action: 'later',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('あとで (プール維持)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      _resetGachaTimer();
                      final msg = await state.recordGachaAction(
                        item: gacha,
                        action: 'dropped',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('もう興味ない (ログへ)'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfileCard(BuildContext context, TodayData data) {
    final cs = Theme.of(context).colorScheme;
    final p = data.profile;

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
                Icon(Icons.person_pin_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '「今の私」プロファイルボード (Obsidian Vault自動抽出)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.currentFocus,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            const Text(
              '🚀 進行中プロジェクト / 締切',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
            ),
            const SizedBox(height: 4),
            ...p.activeProjects.map(
              (proj) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $proj', style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '🎮 いまやってる・見てるもの (`いまやってる・見てるもの.md`)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.doingNowItems
                  .map(
                    (item) => Chip(
                      label: Text(item, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 現在の関心トピック（AIキュレーション連動）',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.currentInterests
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            Text(
              '💰 スタイル: ${p.budgetAndLifestyleNote}',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
