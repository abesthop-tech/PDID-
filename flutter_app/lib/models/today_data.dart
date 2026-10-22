class WeatherInfo {
  final String locationName;
  final String condition;
  final String icon;
  final double temperature;
  final double tempMax;
  final double tempMin;
  final int precipitationProbability;
  final String advice;

  const WeatherInfo({
    required this.locationName,
    required this.condition,
    required this.icon,
    required this.temperature,
    required this.tempMax,
    required this.tempMin,
    required this.precipitationProbability,
    required this.advice,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      locationName: (json['location_name'] ?? json['locationName'] ?? '三軒茶屋・世田谷').toString(),
      condition: (json['condition'] ?? json['summary'] ?? '晴れ時々曇り').toString(),
      icon: (json['icon'] ?? '⛅').toString(),
      temperature: _toDouble(json['temperature'] ?? json['temp'], 19.5),
      tempMax: _toDouble(json['temp_max'] ?? json['tempMax'], 22.0),
      tempMin: _toDouble(json['temp_min'] ?? json['tempMin'], 14.0),
      precipitationProbability: _toInt(
        json['precipitation_probability'] ?? json['rain_prob'] ?? json['precipitationProbability'],
        10,
      ),
      advice: (json['advice'] ?? '夜は少し冷えるので薄手の羽織ものがあると安心です。').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'location_name': locationName,
        'condition': condition,
        'icon': icon,
        'temperature': temperature,
        'temp_max': tempMax,
        'temp_min': tempMin,
        'precipitation_probability': precipitationProbability,
        'advice': advice,
      };
}

class ScheduleEvent {
  final String id;
  final String title;
  final String startTime;
  final String endTime;
  final String location;
  final String category;
  final bool isAllDay;

  const ScheduleEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location = '',
    this.category = 'schedule',
    this.isAllDay = false,
  });

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) {
    return ScheduleEvent(
      id: (json['id'] ?? json['title'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      title: (json['title'] ?? json['summary'] ?? '予定').toString(),
      startTime: (json['start_time'] ?? json['startTime'] ?? json['time'] ?? '10:00').toString(),
      endTime: (json['end_time'] ?? json['endTime'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      category: (json['category'] ?? 'schedule').toString(),
      isAllDay: json['is_all_day'] == true || json['isAllDay'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start_time': startTime,
        'end_time': endTime,
        'location': location,
        'category': category,
        'is_all_day': isAllDay,
      };
}

class ObsidianTask {
  final String id;
  final String text;
  final bool completed;
  final String section; // 'routine' | 'must' | 'want' | 'idea'
  final String sourceFile;
  final int? lineNumber;

  const ObsidianTask({
    required this.id,
    required this.text,
    required this.completed,
    required this.section,
    this.sourceFile = '01_Inbox/やるメモ.md',
    this.lineNumber,
  });

  ObsidianTask copyWith({
    String? id,
    String? text,
    bool? completed,
    String? section,
    String? sourceFile,
    int? lineNumber,
  }) {
    return ObsidianTask(
      id: id ?? this.id,
      text: text ?? this.text,
      completed: completed ?? this.completed,
      section: section ?? this.section,
      sourceFile: sourceFile ?? this.sourceFile,
      lineNumber: lineNumber ?? this.lineNumber,
    );
  }

  factory ObsidianTask.fromJson(Map<String, dynamic> json) {
    return ObsidianTask(
      id: (json['id'] ?? json['line_number'] ?? json['text'] ?? '').toString(),
      text: (json['text'] ?? json['title'] ?? '').toString(),
      completed: json['completed'] == true || json['done'] == true || json['checked'] == true,
      section: (json['section'] ?? json['category'] ?? 'must').toString(),
      sourceFile: (json['source_file'] ?? json['sourceFile'] ?? '01_Inbox/やるメモ.md').toString(),
      lineNumber: json['line_number'] is int
          ? json['line_number'] as int
          : int.tryParse((json['line_number'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'completed': completed,
        'section': section,
        'source_file': sourceFile,
        'line_number': lineNumber,
      };
}

class AiProposal {
  final String id;
  final String timeSlot;
  final String title;
  final String reason;
  final String actionType; // 'must' | 'want' | 'gacha' | 'rest'
  final int estimatedMinutes;

  const AiProposal({
    required this.id,
    required this.timeSlot,
    required this.title,
    required this.reason,
    this.actionType = 'want',
    this.estimatedMinutes = 30,
  });

  factory AiProposal.fromJson(Map<String, dynamic> json) {
    return AiProposal(
      id: (json['id'] ?? json['title'] ?? '').toString(),
      timeSlot: (json['time_slot'] ?? json['timeSlot'] ?? '帰宅後 30分').toString(),
      title: (json['title'] ?? '').toString(),
      reason: (json['reason'] ?? json['description'] ?? '').toString(),
      actionType: (json['action_type'] ?? json['actionType'] ?? 'want').toString(),
      estimatedMinutes: _toInt(json['estimated_minutes'] ?? json['estimatedMinutes'], 30),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'time_slot': timeSlot,
        'title': title,
        'reason': reason,
        'action_type': actionType,
        'estimated_minutes': estimatedMinutes,
      };
}

class HobbyGachaItem {
  final String id;
  final String title;
  final String category; // 'GAME' | 'STORY' | 'SINGLE' | 'ALL'
  final String sourceFile;
  final String trialRule;
  final String? noteLink;
  final String? recommendationNote;

  const HobbyGachaItem({
    required this.id,
    required this.title,
    required this.category,
    required this.sourceFile,
    this.trialRule = '1話 / 1章 / 30分だけ試食する',
    this.noteLink,
    this.recommendationNote,
  });

  String get categoryLabel {
    switch (category.toUpperCase()) {
      case 'GAME':
        return '🎮 ゲーム (したいゲーム.md)';
      case 'STORY':
        return '📖 物語・アニメ (見たい物語.md)';
      case 'SINGLE':
        return '✨ 単発やりたい (単発 やりたいリスト.md)';
      default:
        return '🎲 趣味ガチャ ($category)';
    }
  }

  factory HobbyGachaItem.fromJson(Map<String, dynamic> json) {
    final cat = (json['category'] ?? 'GAME').toString().toUpperCase();
    String defaultSource = '01_Inbox/したいゲーム.md';
    if (cat == 'STORY') defaultSource = '01_Inbox/見たい物語.md';
    if (cat == 'SINGLE') defaultSource = '01_Inbox/単発 やりたいリスト.md';

    return HobbyGachaItem(
      id: (json['id'] ?? json['title'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      title: (json['title'] ?? json['name'] ?? '未設定の趣味アイテム').toString(),
      category: cat,
      sourceFile: (json['source_file'] ?? json['sourceFile'] ?? defaultSource).toString(),
      trialRule: (json['trial_rule'] ?? json['trialRule'] ?? '1話 / 1章 / 30分だけ試食する').toString(),
      noteLink: json['note_link']?.toString(),
      recommendationNote: (json['recommendation_note'] ?? json['reason'] ?? 'まずは30分だけタイマーを回して触ってみましょう！').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'source_file': sourceFile,
        'trial_rule': trialRule,
        'note_link': noteLink,
        'recommendation_note': recommendationNote,
      };
}

class UserProfileSummary {
  final String currentFocus;
  final List<String> activeProjects;
  final List<String> currentInterests;
  final List<String> doingNowItems;
  final String budgetAndLifestyleNote;
  final String lastSyncedAt;

  const UserProfileSummary({
    required this.currentFocus,
    required this.activeProjects,
    required this.currentInterests,
    required this.doingNowItems,
    required this.budgetAndLifestyleNote,
    required this.lastSyncedAt,
  });

  factory UserProfileSummary.fromJson(Map<String, dynamic> json) {
    return UserProfileSummary(
      currentFocus: (json['current_focus'] ??
              json['currentFocus'] ??
              '10月26日締切の制作タスクを進めつつ、夜はComfyUIと短時間の趣味試食でリフレッシュ')
          .toString(),
      activeProjects: _toStringList(
        json['active_projects'] ?? json['activeProjects'],
        const ['10月26日までに完成させる制作課題', 'Daily Concierge (Obsidian×AIハブ)', 'ComfyUI ローカルワークフロー検証'],
      ),
      currentInterests: _toStringList(
        json['current_interests'] ?? json['currentInterests'],
        const ['ローカルAI / ComfyUI', 'Quest 3 / VR', 'Steamインディーゲーム', '哲学・物語構造', '三軒茶屋コスパスポット'],
      ),
      doingNowItems: _toStringList(
        json['doing_now_items'] ?? json['doingNowItems'] ?? json['doing_now'],
        const ['ダンジョン飯 (見返し)', 'Balatro (1日1ラン)', '技術書・AI論文つまみ読み'],
      ),
      budgetAndLifestyleNote: (json['budget_and_lifestyle_note'] ??
              json['budget_note'] ??
              '無理のない予算感で、無料のOSSツールやセール情報・近場の安い良店を賢く活用するモード')
          .toString(),
      lastSyncedAt: (json['last_synced_at'] ?? json['lastSyncedAt'] ?? '今日 08:30 (Obsidian Vault同期済)').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'current_focus': currentFocus,
        'active_projects': activeProjects,
        'current_interests': currentInterests,
        'doing_now_items': doingNowItems,
        'budget_and_lifestyle_note': budgetAndLifestyleNote,
        'last_synced_at': lastSyncedAt,
      };
}

class TodayData {
  final String dateText;
  final String greeting;
  final WeatherInfo weather;
  final List<ScheduleEvent> schedule;
  final List<ObsidianTask> tasks;
  final List<AiProposal> proposals;
  final HobbyGachaItem? currentGacha;
  final UserProfileSummary profile;
  final String vaultPath;
  final bool isOfflineFallback;

  const TodayData({
    required this.dateText,
    required this.greeting,
    required this.weather,
    required this.schedule,
    required this.tasks,
    required this.proposals,
    this.currentGacha,
    required this.profile,
    this.vaultPath = r'\\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs',
    this.isOfflineFallback = false,
  });

  List<ObsidianTask> get routineTasks =>
      tasks.where((t) => t.section == 'routine').toList();

  List<ObsidianTask> get mustTasks =>
      tasks.where((t) => t.section == 'must').toList();

  List<ObsidianTask> get wantTasks =>
      tasks.where((t) => t.section == 'want' || t.section == 'idea').toList();

  TodayData copyWith({
    String? dateText,
    String? greeting,
    WeatherInfo? weather,
    List<ScheduleEvent>? schedule,
    List<ObsidianTask>? tasks,
    List<AiProposal>? proposals,
    HobbyGachaItem? currentGacha,
    UserProfileSummary? profile,
    String? vaultPath,
    bool? isOfflineFallback,
  }) {
    return TodayData(
      dateText: dateText ?? this.dateText,
      greeting: greeting ?? this.greeting,
      weather: weather ?? this.weather,
      schedule: schedule ?? this.schedule,
      tasks: tasks ?? this.tasks,
      proposals: proposals ?? this.proposals,
      currentGacha: currentGacha ?? this.currentGacha,
      profile: profile ?? this.profile,
      vaultPath: vaultPath ?? this.vaultPath,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
    );
  }

  factory TodayData.fromJson(Map<String, dynamic> json) {
    final rawTasks = <ObsidianTask>[];
    if (json['tasks'] is List) {
      for (final item in (json['tasks'] as List)) {
        if (item is Map<String, dynamic>) {
          rawTasks.add(ObsidianTask.fromJson(item));
        }
      }
    } else if (json['tasks'] is Map<String, dynamic>) {
      final taskMap = json['tasks'] as Map<String, dynamic>;
      for (final entry in taskMap.entries) {
        if (entry.value is List) {
          for (final t in (entry.value as List)) {
            if (t is Map<String, dynamic>) {
              rawTasks.add(ObsidianTask.fromJson({...t, 'section': entry.key}));
            }
          }
        }
      }
    }

    final rawSchedule = <ScheduleEvent>[];
    if (json['schedule'] is List) {
      for (final item in (json['schedule'] as List)) {
        if (item is Map<String, dynamic>) {
          rawSchedule.add(ScheduleEvent.fromJson(item));
        }
      }
    }

    final rawProposals = <AiProposal>[];
    final proposalsJson = json['proposals'] ?? json['ai_proposals'];
    if (proposalsJson is List) {
      for (final item in proposalsJson) {
        if (item is Map<String, dynamic>) {
          rawProposals.add(AiProposal.fromJson(item));
        }
      }
    }

    HobbyGachaItem? gacha;
    final gachaJson = json['current_gacha'] ?? json['gacha'] ?? json['hobby_gacha'];
    if (gachaJson is Map<String, dynamic>) {
      gacha = HobbyGachaItem.fromJson(gachaJson);
    }

    return TodayData(
      dateText: (json['date_text'] ?? json['date'] ?? '2026年10月22日 (木)').toString(),
      greeting: (json['greeting'] ?? '余計なことを考える手間を減らし、今日の「本当にやりたいこと」に集中しましょう。').toString(),
      weather: json['weather'] is Map<String, dynamic>
          ? WeatherInfo.fromJson(json['weather'] as Map<String, dynamic>)
          : const WeatherInfo(
              locationName: '三軒茶屋・世田谷',
              condition: '秋晴れ・快適',
              icon: '☀️',
              temperature: 20.0,
              tempMax: 22.0,
              tempMin: 13.5,
              precipitationProbability: 10,
              advice: '日中は過ごしやすい陽気です。帰りが20時以降なら薄手の上着を。',
            ),
      schedule: rawSchedule,
      tasks: rawTasks,
      proposals: rawProposals,
      currentGacha: gacha,
      profile: json['profile'] is Map<String, dynamic>
          ? UserProfileSummary.fromJson(json['profile'] as Map<String, dynamic>)
          : UserProfileSummary.fromJson(const {}),
      vaultPath: (json['vault_path'] ?? r'\\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs').toString(),
      isOfflineFallback: json['is_offline_fallback'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'date_text': dateText,
        'greeting': greeting,
        'weather': weather.toJson(),
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'proposals': proposals.map((e) => e.toJson()).toList(),
        'current_gacha': currentGacha?.toJson(),
        'profile': profile.toJson(),
        'vault_path': vaultPath,
        'is_offline_fallback': isOfflineFallback,
      };
}

double _toDouble(dynamic value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _toInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

List<String> _toStringList(dynamic value, List<String> fallback) {
  if (value is List) {
    return value.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  return fallback;
}
