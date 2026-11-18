import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'features/widget/quick_add_popup.dart';

Future<ProviderScope> _boot(Widget Function() child, {Future<void> Function(SharedPreferences)? onPrefs}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await onPrefs?.call(prefs);
  return ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: child());
}

Future<void> main() async {
  runApp(await _boot(() => const MyFinanceApp(), onPrefs: (p) async {
    // "Sembunyikan saldo saat aplikasi dibuka": simpan status efektif agar popup/widget konsisten.
    if (p.getBool(SettingsNotifier.kHideOnStart) ?? false) await p.setBool(SettingsNotifier.kHidden, true);
  }));
}

/// Entrypoint terpisah untuk popup catat cepat (dipanggil dari QuickAddActivity).
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  final route = PlatformDispatcher.instance.defaultRouteName;
  runApp(await _boot(() => QuickAddApp(route: route)));
}
