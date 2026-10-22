import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'screens/today_screen.dart';
import 'screens/sns_feed_screen.dart';
import 'screens/curation_screen.dart';
import 'screens/sources_settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final conciergeState = ConciergeState();
  // 非同期でキャッシュ読み込み＆サーバー接続確認を開始
  conciergeState.initialize();

  runApp(
    ChangeNotifierProvider<ConciergeState>.value(
      value: conciergeState,
      child: const DailyConciergeApp(),
    ),
  );
}

class DailyConciergeApp extends StatelessWidget {
  const DailyConciergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF111318),
    );

    return MaterialApp(
      title: 'Daily Concierge',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        cardTheme: const CardThemeData(
          color: Color(0xFF171A22),
          margin: EdgeInsets.zero,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111318),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const ResponsiveConciergeShell(),
    );
  }
}

class ResponsiveConciergeShell extends StatefulWidget {
  const ResponsiveConciergeShell({super.key});

  @override
  State<ResponsiveConciergeShell> createState() =>
      _ResponsiveConciergeShellState();
}

class _ResponsiveConciergeShellState extends State<ResponsiveConciergeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    TodayScreen(),
    SnsFeedScreen(),
    CurationScreen(),
    SourcesSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConciergeState>();
    final unreadCount = state.unreadFeedItems.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopWide = constraints.maxWidth >= 800;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Concierge',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '余計なことを考える手間を減らし、今の私を明瞭にする情報ハブ',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (state.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: '最新データに同期・更新',
                  onPressed: state.refreshAll,
                  icon: const Icon(Icons.sync),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (isDesktopWide) ...[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) {
                    setState(() {
                      _selectedIndex = idx;
                    });
                  },
                  extended: constraints.maxWidth >= 1120,
                  backgroundColor: const Color(0xFF111318),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.wb_sunny_outlined),
                      selectedIcon: Icon(Icons.wb_sunny),
                      label: Text('① Today & 提案'),
                    ),
                    NavigationRailDestination(
                      icon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.dynamic_feed_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.dynamic_feed),
                      ),
                      label: const Text('② SNS差分フィード'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.auto_stories_outlined),
                      selectedIcon: Icon(Icons.auto_stories),
                      label: Text('③ AI・お得・読み物'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('④ ソース・設定'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
              ],
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktopWide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) {
                    setState(() {
                      _selectedIndex = idx;
                    });
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.wb_sunny_outlined),
                      selectedIcon: Icon(Icons.wb_sunny),
                      label: 'Today & 提案',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.dynamic_feed_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.dynamic_feed),
                      ),
                      label: 'SNS差分',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.auto_stories_outlined),
                      selectedIcon: Icon(Icons.auto_stories),
                      label: 'AI・お得・記事',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: 'ソース・設定',
                    ),
                  ],
                ),
        );
      },
    );
  }
}
