import 'dart:io';

import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/summary.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');
  // "sekarang" tetap: Rabu 18 Nov 2026 12:00 lokal
  final now = DateTime(2026, 11, 18, 12);

  late AppDatabase db;
  late Repository repo;
  late int food, transport, salary;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    final cats = await repo.watchAllCategories().first;
    food = cats.firstWhere((c) => c.name == 'Makan & Minum').id;
    transport = cats.firstWhere((c) => c.name == 'Transportasi').id;
    salary = cats.firstWhere((c) => c.name == 'Gaji').id;
  });
  tearDown(() => db.close());

  Future<void> add(TxType t, int minor, dynamic cur, int cat, DateTime at, [String note = '']) =>
      repo.addTransaction(
          type: t, money: Money(minor, cur), categoryId: cat, occurredAt: at, note: note);

  group('migrasi / seed', () {
    test('onCreate membuat tabel dan mengisi kategori bawaan', () async {
      final exp = await repo.watchCategories(TxType.expense).first;
      final inc = await repo.watchCategories(TxType.income).first;
      expect(exp.map((c) => c.name), [
        'Makan & Minum', 'Transportasi', 'Belanja', 'Tagihan', 'Kesehatan', 'Hiburan', 'Pendidikan', 'Lainnya'
      ]);
      expect(inc.map((c) => c.name), ['Gaji', 'Bonus', 'Hadiah', 'Usaha', 'Lainnya']);
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data['user_version'], AppDatabase.currentVersion);
      final idx = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_tx_%'").get();
      expect(idx.length, 2);
      await db.select(db.templates).get(); // tabel templates ada
    });

    test('membuka ulang file yang sudah ada tidak menyemai ulang', () async {
      // simulasi file DB ada di disk: pakai file sementara
      final dir = Directory.systemTemp.createTempSync('myfinance_mig');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/mig.db');
      final d1 = AppDatabase(NativeDatabase(f));
      final n1 = (await d1.select(d1.categories).get()).length;
      await d1.close();
      final d2 = AppDatabase(NativeDatabase(f));
      final n2 = (await d2.select(d2.categories).get()).length;
      await d2.close();
      expect(n1, 13);
      expect(n2, 13);
    });
  });

  group('filter gabungan', () {
    setUp(() async {
      await add(TxType.expense, 18000, idr, food, DateTime(2026, 11, 18, 8), 'Kopi pagi');
      await add(TxType.expense, 50000, idr, transport, DateTime(2026, 11, 17, 9), 'Ojek');
      await add(TxType.expense, 1250, usd, food, DateTime(2026, 11, 2, 9), 'coffee 50% off');
      await add(TxType.income, 5000000, idr, salary, DateTime(2026, 11, 1, 9), 'Gaji');
      await add(TxType.expense, 99000, idr, food, DateTime(2026, 10, 30, 23, 30), 'Bulan lalu');
    });

    Future<int> count(TxFilter f) async => (await repo.rows(f, now: now)).length;

    test('periode cepat', () async {
      expect(await count(const TxFilter(period: QuickPeriod.all)), 5);
      expect(await count(const TxFilter(period: QuickPeriod.month)), 4);
      expect(await count(const TxFilter(period: QuickPeriod.week)), 2); // Sen 16 - Min 22
      expect(await count(const TxFilter(period: QuickPeriod.today)), 1);
    });

    test('rentang kustom inklusif, mengalahkan periode', () async {
      final f = TxFilter(customRange: DayRange(DateTime(2026, 10, 30), DateTime(2026, 11, 1)));
      expect(await count(f), 2);
    });

    test('jenis, kategori, mata uang', () async {
      expect(await count(const TxFilter(period: QuickPeriod.all, type: TxType.income)), 1);
      expect(await count(TxFilter(period: QuickPeriod.all, categoryIds: {food})), 3);
      expect(await count(const TxFilter(period: QuickPeriod.all, currencies: {'USD'})), 1);
    });

    test('kata kunci: tidak peka huruf, % dan _ dianggap huruf biasa', () async {
      expect(await count(const TxFilter(period: QuickPeriod.all, query: 'KOPI')), 1);
      expect(await count(const TxFilter(period: QuickPeriod.all, query: '50%')), 1);
      expect(await count(const TxFilter(period: QuickPeriod.all, query: '%')), 1);
      expect(await count(const TxFilter(period: QuickPeriod.all, query: '_')), 0);
    });

    test('digabung (AND)', () async {
      final f = TxFilter(
        period: QuickPeriod.month,
        type: TxType.expense,
        categoryIds: {food},
        currencies: const {'IDR'},
        query: 'kopi',
      );
      final r = await repo.rows(f, now: now);
      expect(r.single.tx.note, 'Kopi pagi');
    });

    test('urutan terbaru dulu', () async {
      final r = await repo.rows(TxFilter.all, now: now);
      final times = r.map((e) => e.tx.occurredAt).toList();
      expect(times, [...times]..sort((a, b) => b.compareTo(a)));
    });

    test('kategori terarsip: transaksi lama tetap muncul', () async {
      await repo.setArchived(food, true);
      expect(await count(const TxFilter(period: QuickPeriod.all)), 5);
      final active = await repo.watchCategories(TxType.expense).first;
      expect(active.any((c) => c.id == food), isFalse);
    });

    test('kategori diurut menurut frekuensi pakai', () async {
      final l = await repo.watchCategoriesByUsage(TxType.expense).first;
      expect(l.first.id, food); // 3 pemakaian
      expect(l[1].id, transport);
    });

    test('hapus + urungkan', () async {
      final row = (await repo.rows(TxFilter.all, now: now)).first;
      await repo.deleteTransaction(row.tx.id);
      expect(await count(TxFilter.all), 4);
      await repo.restoreTransaction(row.tx);
      final back = await repo.rows(TxFilter.all, now: now);
      expect(back.length, 5);
      expect(back.first.tx.id, row.tx.id);
    });
  });

  group('rekap per mata uang', () {
    test('tidak pernah menjumlah mata uang berbeda', () async {
      await add(TxType.expense, 18000, idr, food, now);
      await add(TxType.expense, 2000, idr, food, now);
      await add(TxType.income, 5000000, idr, salary, now);
      await add(TxType.expense, 1250, usd, food, now);
      await add(TxType.income, 10000, usd, salary, now);
      final t = await repo.totals(TxFilter.all, now: now);
      expect(t.length, 2);
      final i = t.firstWhere((e) => e.currency.code == 'IDR');
      expect(i.expenseMinor, 20000);
      expect(i.incomeMinor, 5000000);
      expect(i.net.minor, 4980000);
      final u = t.firstWhere((e) => e.currency.code == 'USD');
      expect(u.expenseMinor, 1250);
      expect(u.incomeMinor, 10000);
      expect(u.net.minor, 8750);
    });

    test('kosong menghasilkan daftar kosong', () => expect(summarize(const []), isEmpty));
  });
}
