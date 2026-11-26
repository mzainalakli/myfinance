import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/app.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/core/providers.dart';
import 'package:myfinance/core/strings.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/ui/common.dart';
import 'package:myfinance/features/transactions/ui/numpad.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sheet (pencatatan, filter, pemilih mata uang) harus menutupi SELURUH layar, termasuk FAB dan bar
/// navigasi milik AppShell, apa pun cara membukanya. Bug sebelumnya: sheet yang dibuka dari halaman tab
/// terpasang di Navigator cabang (seluas isi tab), sehingga FAB "+ Catat" tampil di atas numpad dan
/// menutupi tombol hapus. Memakai router SUNGGUHAN (buildRouter), bukan Scaffold tiruan.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');

  AppDatabase? openDb;

  Future<void> shutdown(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
    await t.runAsync(() async => openDb?.close());
  }

  void tw(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, (t) async {
        await body(t);
        await shutdown(t);
      });

  Future<void> boot(WidgetTester t, Size size, double scale, String route) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    openDb = db;
    await t.runAsync(() async {
      final repo = Repository(db);
      final cats = await repo.watchCategories(TxType.expense).first;
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await repo.addTransaction(
          type: TxType.expense,
          money: Money(1000 + i, idr),
          categoryId: cats[i % cats.length].id,
          note: 'catatan $i',
          // Deterministik terhadap jam & zona waktu mesin (satu hari, tengah hari).
          occurredAt: DateTime(now.year, now.month, now.day, 12).subtract(Duration(minutes: i)),
        );
      }
    });
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        dbProvider.overrideWithValue(db),
      ],
      child: MyFinanceApp(router: buildRouter(initialLocation: route)),
    ));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  /// Navigator akar = Navigator terluar di pohon.
  NavigatorState rootNav(WidgetTester t) => t.state<NavigatorState>(find.byType(Navigator).first);

  void expectShellCovered(WidgetTester t, String where) {
    expect(find.byType(FloatingActionButton).hitTestable(), findsNothing,
        reason: '$where: FAB masih bisa diketuk di atas sheet');
    expect(find.byType(NavigationBar).hitTestable(), findsNothing,
        reason: '$where: bar navigasi masih bisa diketuk di bawah/di atas sheet');
  }

  void expectNumpadUsable(WidgetTester t, String where) {
    expect(find.byType(Numpad), findsOneWidget, reason: '$where: sheet pencatatan tidak terbuka');
    final keys = find.descendant(of: find.byType(Numpad), matching: find.byType(InkWell));
    expect(keys.hitTestable(), findsNWidgets(12), reason: '$where: ada tombol numpad yang tertutup');
    expect(find.byIcon(Icons.backspace_outlined).hitTestable(), findsOneWidget,
        reason: '$where: tombol hapus tertutup');
  }

  const configs = [(Size(360, 800), 1.0), (Size(411, 891), 1.3)];
  for (final (size, scale) in configs) {
    final tag = '${size.width.toInt()}x${size.height.toInt()} teks x$scale';

    tw('sheet dari tombol FAB menutupi FAB dan bar navigasi: $tag', (t) async {
      await boot(t, size, scale, '/history');
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
      await t.tap(find.byType(FloatingActionButton));
      await settle(t);
      expectShellCovered(t, 'FAB');
      expectNumpadUsable(t, 'FAB');
      rootNav(t).pop();
      await settle(t);
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget,
          reason: 'FAB harus bisa diketuk lagi setelah sheet ditutup');
    });

    tw('sheet dari ketuk transaksi di Riwayat menutupi FAB: $tag', (t) async {
      await boot(t, size, scale, '/history');
      await t.tap(find.byType(TxTile).first);
      await settle(t);
      expectShellCovered(t, 'Riwayat');
      expectNumpadUsable(t, 'Riwayat');
    });

    tw('sheet dari ketuk transaksi di Beranda menutupi FAB: $tag', (t) async {
      await boot(t, size, scale, '/home');
      await t.tap(find.byType(TxTile).first);
      await settle(t);
      expectShellCovered(t, 'Beranda');
      expectNumpadUsable(t, 'Beranda');
    });

    tw('sheet filter menutupi FAB dan bar navigasi: $tag', (t) async {
      await boot(t, size, scale, '/history');
      await t.tap(find.byTooltip(S.filter));
      await settle(t);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'sheet filter tidak terbuka');
      expectShellCovered(t, 'Filter');
    });

    tw('pemilih mata uang (di dalam sheet) menutupi FAB dan bar navigasi: $tag', (t) async {
      await boot(t, size, scale, '/history');
      await t.tap(find.byType(FloatingActionButton));
      await settle(t);
      await t.tap(find.text('Rp · IDR'));
      await settle(t);
      expect(find.byType(BottomSheet), findsNWidgets(2), reason: 'pemilih mata uang tidak terbuka');
      expectShellCovered(t, 'Pemilih mata uang');
    });
  }
}
