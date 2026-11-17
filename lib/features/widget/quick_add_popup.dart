import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/app_config.dart';
import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../transactions/ui/quick_add_sheet.dart';

/// Popup catat cepat: Activity transparan di atas layar utama, tanpa membuka aplikasi penuh.
/// Rute awal dari Kotlin: `/quick/expense` atau `/quick/income`.
class QuickAddApp extends ConsumerWidget {
  final String route;
  const QuickAddApp({super.key, required this.route});

  TxType get _type => route.contains('income') ? TxType.income : TxType.expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: appLocalizations,
      home: _Popup(type: _type),
    );
  }
}

class _Popup extends StatelessWidget {
  final TxType type;
  const _Popup({required this.type});

  void _close() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false, // sheet mengatur sendiri inset keyboard
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: ColoredBox(color: Colors.black.withValues(alpha: .45)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: .4), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                QuickAddSheet(initialType: type, onDone: _close),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
