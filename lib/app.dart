import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_config.dart';
import 'core/providers.dart';
import 'core/strings.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/categories_page.dart';
import 'features/settings/settings_page.dart';
import 'features/stats/stats_page.dart';
import 'features/transactions/ui/history_page.dart';
import 'features/transactions/ui/home_page.dart';
import 'features/transactions/ui/quick_add_sheet.dart';
import 'features/widget/widget_service.dart';

const appLocalizations = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final _router = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomePage())]),
        StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryPage())]),
        StatefulShellBranch(routes: [GoRoute(path: '/stats', builder: (_, _) => const StatsPage())]),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsPage(),
      routes: [GoRoute(path: 'categories', builder: (_, _) => const CategoriesPage())],
    ),
  ],
);

class MyFinanceApp extends ConsumerStatefulWidget {
  const MyFinanceApp({super.key});
  @override
  ConsumerState<MyFinanceApp> createState() => _MyFinanceAppState();
}

class _MyFinanceAppState extends ConsumerState<MyFinanceApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWidget());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncWidget() => WidgetService.refresh(ref.read(repoProvider), ref.read(settingsProvider));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Popup widget menulis lewat koneksi/engine lain: beri tahu stream di sini.
      ref.read(dbProvider).refreshAll();
      ref.invalidate(rowsProvider);
      _syncWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: appLocalizations,
      routerConfig: _router,
    );
  }
}

class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showQuickAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text(S.record),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: S.home),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: S.history),
          NavigationDestination(icon: Icon(Icons.insert_chart_outlined), selectedIcon: Icon(Icons.insert_chart), label: S.stats),
        ],
      ),
    );
  }
}
