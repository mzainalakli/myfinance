import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_config.dart';
import 'core/providers.dart';
import 'core/strings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'features/settings/categories_page.dart';
import 'features/settings/import_page.dart';
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

GoRouter buildRouter({String initialLocation = '/home'}) => GoRouter(
  initialLocation: initialLocation,
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
      routes: [
        GoRoute(path: 'categories', builder: (_, _) => const CategoriesPage()),
        GoRoute(path: 'import', builder: (_, _) => const ImportPage()),
      ],
    ),
  ],
);

final _router = buildRouter();

class MyFinanceApp extends ConsumerStatefulWidget {
  /// [router] hanya untuk pengujian; aplikasi memakai router bawaan.
  final GoRouter? router;
  const MyFinanceApp({super.key, this.router});
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
      routerConfig: widget.router ?? _router,
    );
  }
}

/// Kerangka tiga tab + satu-satunya FAB aplikasi. Aturan FAB (berlaku di semua tab, lihat DECISIONS.md):
/// konten tidak boleh punya kontrol di jalur FAB (filter di atas, bukan di bawah), daftar memberi ruang
/// bawah [Tk.fabClearance], FAB menyusut saat menggulir ke bawah, dan disembunyikan saat keyboard muncul.
class AppShell extends StatefulWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool extended = true;

  void _setExtended(bool v) {
    if (v != extended) setState(() => extended = v);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false; // chip filter yang digeser mendatar diabaikan
    if (n is UserScrollNotification) {
      // reverse = isi naik (menggulir ke bawah): susut. forward = ke atas: tampil lagi.
      // idle diabaikan: itu hanya jari terangkat, gulir lanjutan (fling) masih berjalan.
      if (n.direction == ScrollDirection.reverse) _setExtended(false);
      if (n.direction == ScrollDirection.forward) _setExtended(true);
    } else if (n is ScrollEndNotification) {
      _setExtended(true); // daftar benar-benar berhenti
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: shell),
      floatingActionButton: AnimatedScale(
        scale: keyboard ? 0 : 1,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: keyboard,
          child: FloatingActionButton.extended(
            isExtended: extended,
            tooltip: S.record,
            onPressed: () => showQuickAddSheet(context),
            icon: const Icon(Icons.add),
            label: const Text(S.record),
          ),
        ),
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
