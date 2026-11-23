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
import 'package:myfinance/features/settings/categories_page.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mencegah FAB menutupi kontrol yang bisa diketuk di layar mana pun yang memakai FAB
/// (semua tab di bawah AppShell). Ukuran 360x640 dan 411x891, skala teks 1.0 dan 1.3,
/// posisi gulir awal dan akhir.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');

  AppDatabase? openDb;

  /// Lepas pohon widget lebih dulu (timer penutup stream drift), baru tutup DB. Dipanggil di akhir tiap tes.
  Future<void> shutdown(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
    await t.runAsync(() async => openDb?.close());
  }

  /// Seperti testWidgets, tetapi selalu membereskan di akhir.
  void tw(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        await body(t);
        await shutdown(t);
      });

  Future<void> boot(WidgetTester t, Size size, double scale, String route, {required int rows}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    openDb = db;
    await t.runAsync(() async {
      final repo = Repository(db);
      final cats = await repo.watchCategories(TxType.expense).first;
      final now = DateTime.now();
      for (var i = 0; i < rows; i++) {
        await repo.addTransaction(
          type: TxType.expense,
          money: Money(1000 + i, idr),
          categoryId: cats[i % cats.length].id,
          note: 'catatan $i',
          occurredAt: now.subtract(Duration(hours: i * 7)),
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

  /// Rect semua kontrol yang bisa diketuk. [includeTiles]: ListTile/baris transaksi juga dihitung.
  List<(String, Rect)> tappables(WidgetTester t, {required bool includeTiles}) {
    final finders = <String, Finder>{
      'button': find.byWidgetPredicate((w) => w is ButtonStyleButton),
      'chip': find.byWidgetPredicate((w) => w is RawChip),
      if (includeTiles) 'tile': find.byType(ListTile),
    };
    final out = <(String, Rect)>[];
    for (final e in finders.entries) {
      for (final el in e.value.evaluate()) {
        final box = el.renderObject as RenderBox?;
        if (box == null || !box.hasSize || !box.attached) continue;
        out.add((e.key, box.localToGlobal(Offset.zero) & box.size));
      }
    }
    return out;
  }

  Finder mainScrollable(WidgetTester t) => find
      .byWidgetPredicate((w) => w is Scrollable && (w.axis == Axis.vertical))
      .first;

  void expectNoOverlap(WidgetTester t, Rect fab, {required bool includeTiles, required String where}) {
    final bad = [
      for (final (kind, r) in tappables(t, includeTiles: includeTiles))
        if (r.overlaps(fab)) '$kind $r',
    ];
    expect(bad, isEmpty, reason: '$where: kontrol beririsan dengan FAB $fab');
  }

  const sizes = [Size(360, 640), Size(411, 891)];
  const scales = [1.0, 1.3];
  const routes = ['/home', '/history', '/stats'];

  for (final route in routes) {
    for (final size in sizes) {
      for (final scale in scales) {
        final tag = '$route ${size.width.toInt()}x${size.height.toInt()} teks x$scale';

        tw('FAB tidak menutupi kontrol, data banyak: $tag', (t) async {
          await boot(t, size, scale, route, rows: 60);
          final fab = t.getRect(find.byType(FloatingActionButton));
          // awal: semua tombol/chip bebas (baris daftar yang bergulir di bawah FAB wajar di posisi awal)
          expectNoOverlap(t, fab, includeTiles: false, where: '$tag awal');
          // akhir: semua kontrol, termasuk baris, bebas
          final sc = t.state<ScrollableState>(mainScrollable(t));
          sc.position.jumpTo(sc.position.maxScrollExtent);
          await t.pump(const Duration(milliseconds: 300));
          expectNoOverlap(t, fab, includeTiles: true, where: '$tag akhir');
        });

        tw('FAB tidak menutupi kontrol, data sedikit: $tag', (t) async {
          await boot(t, size, scale, route, rows: 2);
          final fab = t.getRect(find.byType(FloatingActionButton));
          expectNoOverlap(t, fab, includeTiles: true, where: '$tag awal');
        });
      }
    }
  }

  group('perilaku FAB', () {
    tw('menyusut saat menggulir ke bawah, muncul lagi saat ke atas atau saat berhenti', (t) async {
      await boot(t, const Size(411, 891), 1.0, '/history', rows: 60);
      double fabSize() => t.getSize(find.byType(FloatingActionButton)).width;
      final full = fabSize();
      expect(full, greaterThan(70));
      final g = await t.startGesture(t.getCenter(mainScrollable(t)));
      await g.moveBy(const Offset(0, -150));
      await t.pump();
      await g.moveBy(const Offset(0, -150));
      await t.pump(const Duration(milliseconds: 400));
      expect(fabSize(), lessThan(full), reason: 'menyusut saat menggulir ke bawah');
      await g.moveBy(const Offset(0, 120));
      await t.pump(const Duration(milliseconds: 400));
      expect(fabSize(), full, reason: 'tampil lagi saat menggulir ke atas');
      await g.moveBy(const Offset(0, -200));
      await t.pump(const Duration(milliseconds: 400));
      expect(fabSize(), lessThan(full));
      await g.up();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(fabSize(), full, reason: 'tampil lagi saat daftar berhenti');
    });

    tw('menggeser chip filter (mendatar) tidak menyusutkan FAB', (t) async {
      await boot(t, const Size(360, 640), 1.3, '/history', rows: 5);
      final full = t.getSize(find.byType(FloatingActionButton)).width;
      final horiz = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal).first;
      await t.drag(horiz, const Offset(-80, 0));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getSize(find.byType(FloatingActionButton)).width, full);
    });

    tw('snackbar muncul di atas FAB, tidak bersinggungan', (t) async {
      await boot(t, const Size(360, 640), 1.3, '/history', rows: 5);
      final ctx = t.element(find.byType(FloatingActionButton));
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('Catatan dihapus'),
        action: SnackBarAction(label: 'Urungkan', onPressed: () {}),
        duration: const Duration(seconds: 30),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      final fab = t.getRect(find.byType(FloatingActionButton));
      final snack = t.getRect(find.byType(SnackBar));
      expect(snack.overlaps(fab), isFalse, reason: 'snackbar $snack vs FAB $fab');
      expect(snack.bottom, lessThanOrEqualTo(fab.top + 0.5));
      expect(t.getRect(find.byType(SnackBarAction)).overlaps(fab), isFalse);
    });

    tw('sheet pencatatan menutup FAB; FAB hilang saat keyboard muncul', (t) async {
      await boot(t, const Size(411, 891), 1.0, '/home', rows: 3);
      await t.tap(find.byType(FloatingActionButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing, reason: 'tertutup sheet/penghalang');
      Navigator.of(t.element(find.byType(Scaffold).first), rootNavigator: true).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing, reason: 'keyboard terbuka');
    });
  });

  group('Kelola Kategori (tanpa FAB): tombol tambah tidak menutupi baris terakhir', () {
    for (final size in sizes) {
      for (final scale in scales) {
        tw('${size.width.toInt()}x${size.height.toInt()} teks x$scale', (t) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final db = AppDatabase(NativeDatabase.memory());
          openDb = db;
          await t.runAsync(() => Repository(db).watchAllCategories().first); // buka DB + seed
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = size;
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.view.reset);
          addTearDown(t.platformDispatcher.clearAllTestValues);
          await t.pumpWidget(ProviderScope(
            overrides: [sharedPrefsProvider.overrideWithValue(prefs), dbProvider.overrideWithValue(db)],
            child: const MaterialApp(home: CategoriesPage()),
          ));
          for (var i = 0; i < 10; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
          final add = t.getRect(find.widgetWithText(FilledButton, 'Tambah kategori'));
          final sc = t.state<ScrollableState>(mainScrollable(t));
          sc.position.jumpTo(sc.position.maxScrollExtent);
          await t.pump(const Duration(milliseconds: 300));
          final lastTile = find.byType(ListTile).evaluate().last.renderObject! as RenderBox;
          final r = lastTile.localToGlobal(Offset.zero) & lastTile.size;
          expect(r.bottom, lessThanOrEqualTo(add.top + 0.5), reason: 'baris terakhir $r vs tombol $add');
        });
      }
    }
  });
}
