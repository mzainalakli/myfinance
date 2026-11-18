import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/core/providers.dart';
import 'package:myfinance/features/transactions/data/summary.dart';
import 'package:myfinance/features/transactions/ui/common.dart';
import 'package:myfinance/features/widget/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');

  group('pemformat dengan flag hidden', () {
    test('format dan formatNumber memberi topeng tetap (panjang tidak membocorkan angka)', () {
      expect(Money(18000, idr).format(hidden: true), kMask);
      expect(Money(999999999, idr).format(hidden: true), kMask);
      expect(Money(5, usd).formatNumber(hidden: true), kMask);
      expect(Money(-1250, usd).format(hidden: true), kMask, reason: 'tanda minus pun tidak bocor');
      expect(kMask, '••••••');
    });
    test('hidden=false tetap normal', () {
      expect(Money(18000, idr).format(), 'Rp 18.000');
    });
  });

  group('persistensi status', () {
    Future<ProviderContainer> make() async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        dbProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('default: tidak tersembunyi, opsi mati', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await make();
      final s = c.read(settingsProvider);
      expect(s.balanceHidden, isFalse);
      expect(s.hideOnStart, isFalse);
      expect(s.hideHistoryAmounts, isFalse);
      expect(s.historyHidden, isFalse);
    });

    test('toggle tersimpan dan bertahan setelah "aplikasi ditutup" (container baru)', () async {
      SharedPreferences.setMockInitialValues({});
      var c = await make();
      await c.read(settingsProvider.notifier).setBalanceHidden(true);
      expect(c.read(settingsProvider).balanceHidden, isTrue);
      expect(c.read(hiddenProvider), isTrue);
      c.dispose();
      // buka lagi dengan prefs yang sama
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('balance_hidden'), isTrue);
      c = await make();
      expect(c.read(settingsProvider).balanceHidden, isTrue);
      await c.read(settingsProvider.notifier).toggleBalanceHidden();
      expect(c.read(settingsProvider).balanceHidden, isFalse);
    });

    test('opsi riwayat: tersembunyi hanya bila opsi aktif DAN saldo tersembunyi', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await make();
      final n = c.read(settingsProvider.notifier);
      await n.setHideHistoryAmounts(true);
      expect(c.read(settingsProvider).historyHidden, isFalse, reason: 'saldo masih tampil');
      await n.setBalanceHidden(true);
      expect(c.read(settingsProvider).historyHidden, isTrue);
      await n.setHideHistoryAmounts(false);
      expect(c.read(settingsProvider).historyHidden, isFalse);
      expect(c.read(historyHiddenProvider), isFalse);
    });

    test('opsi "sembunyikan saat dibuka" tersimpan', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await make();
      await c.read(settingsProvider.notifier).setHideOnStart(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hide_on_start'), isTrue);
    });
  });

  group('data yang dikirim ke widget', () {
    final now = DateTime(2026, 11, 18, 12);
    final totals = [CurrencyTotal(idr, 5000000, 123456, 3), CurrencyTotal(usd, 100, 250, 1)];

    test('tampil: angka asli', () {
      final p = WidgetService.buildPayload(totals, const AppSettings(), now);
      expect(p['today_expense'], 'Rp 123.456');
      expect(p['today_income'], 'Rp 5.000.000');
      expect(p['today_date'], '2026-11-18');
      expect(p['today_other'], '+1 mata uang lain');
    });

    test('tersembunyi: nilai yang DIKIRIM sudah topeng, tanpa digit sama sekali', () {
      final p = WidgetService.buildPayload(totals, const AppSettings(balanceHidden: true), now);
      expect(p['today_expense'], kMask);
      expect(p['today_income'], kMask);
      for (final k in ['today_expense', 'today_income']) {
        expect(p[k], isNot(matches(RegExp(r'\d'))), reason: k);
      }
      expect(p.values.join(), isNot(contains('123')), reason: 'angka asli tidak ikut terkirim');
    });

    test('tidak ada transaksi hari ini', () {
      final p = WidgetService.buildPayload(const [], const AppSettings(balanceHidden: true), now);
      expect(p['today_expense'], kMask);
    });
  });

  testWidgets('MoneyText: topeng bila hidden, angka bila tidak', (tester) async {
    Widget app(bool hidden) => MaterialApp(
          home: Material(child: MoneyText(Money(18000, idr), style: NumberStyle.id, hidden: hidden, prefix: '-')),
        );
    await tester.pumpWidget(app(false));
    expect(find.text('-Rp 18.000'), findsOneWidget);
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(kMask), findsOneWidget);
    expect(find.textContaining('18'), findsNothing);
  });
}
