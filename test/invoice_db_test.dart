import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/core/csv/transaction_csv.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/features/transactions/data/csv_export.dart';
import 'package:myfinance/features/transactions/data/import_service.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final twd = currencyByCode('TWD');

  group('migrasi v1 -> v2', () {
    test('data lama utuh, kolom baru NULL, tabel penjual dan indeks unik ada', () async {
      final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
        raw.execute('''
CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT NOT NULL, icon TEXT NOT NULL,
  color INTEGER NOT NULL, type TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0);
CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, type TEXT NOT NULL, amount_minor INTEGER NOT NULL,
  currency_code TEXT NOT NULL, category_id INTEGER NOT NULL REFERENCES categories (id), note TEXT NOT NULL DEFAULT '',
  occurred_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE templates (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, category_id INTEGER NOT NULL REFERENCES categories (id),
  amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', sort_order INTEGER NOT NULL DEFAULT 0);
CREATE INDEX idx_tx_occurred ON transactions (occurred_at);
CREATE INDEX idx_tx_category ON transactions (category_id);
INSERT INTO categories (name, icon, color, type, sort_order) VALUES ('Makan', 'restaurant', 4293844992, 'expense', 0);
INSERT INTO transactions (type, amount_minor, currency_code, category_id, note, occurred_at, created_at, updated_at)
  VALUES ('expense', 18000, 'IDR', 1, 'kopi', 1000, 1000, 1000), ('expense', 500, 'USD', 1, '', 2000, 2000, 2000);
PRAGMA user_version = 1;
''');
      }));
      addTearDown(db.close);
      final repo = Repository(db);

      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data['user_version'], 2);

      final rows = await repo.rows(TxFilter.all);
      expect(rows.length, 2);
      expect(rows.map((r) => r.tx.amountMinor).toSet(), {18000, 500});
      expect(rows.every((r) => r.tx.invoiceNo == null), isTrue);
      expect(rows.firstWhere((r) => r.tx.note == 'kopi').category.name, 'Makan');
      expect((await db.select(db.sellers).get()), isEmpty);

      // fungsi baru jalan di DB hasil migrasi: faktur unik, banyak NULL boleh
      final cat = rows.first.category.id;
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: cat, invoiceNo: 'HB35094463');
      await expectLater(
          repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: cat, invoiceNo: 'HB35094463'),
          throwsA(isA<DuplicateInvoiceException>()));
      expect(await repo.countTransactions(), 3);
    });
  });

  group('faktur di database', () {
    late AppDatabase db;
    late Repository repo;
    late int food, shop;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = Repository(db);
      final cats = await repo.watchCategories(TxType.expense).first;
      food = cats.firstWhere((c) => c.name == 'Makan & Minum').id;
      shop = cats.firstWhere((c) => c.name == 'Belanja').id;
    });
    tearDown(() => db.close());

    test('nomor faktur kembar ditolak; indeks unik juga menolak penulisan langsung', () async {
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: food, invoiceNo: 'AB12345678');
      await expectLater(
          repo.addTransaction(type: TxType.expense, money: Money(5, twd), categoryId: food, invoiceNo: 'AB12345678'),
          throwsA(isA<DuplicateInvoiceException>().having((e) => e.existing.amountMinor, 'existing', isNot(5))));
      await expectLater(
        db.customInsert(
            "INSERT INTO transactions (type, amount_minor, currency_code, category_id, occurred_at, created_at, updated_at, nomor_faktur) "
            "VALUES ('expense', 1, 'TWD', $food, 1, 1, 1, 'AB12345678')"),
        throwsA(anything),
      );
      expect(await repo.countTransactions(), 1);
    });

    test('dua transaksi tanpa faktur (NULL) tetap boleh', () async {
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: food);
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: food);
      expect(await repo.countTransactions(), 2);
    });

    test('upsert penjual: kategori diperbarui, nama yang sudah ada tidak ditimpa', () async {
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: food, note: 'Kopi', invoiceNo: 'AA00000001', sellerNpwp: '27258805');
      var s = (await repo.sellerFor('27258805'))!;
      expect([s.categoryId, s.name], [food, 'Kopi']);
      expect((await repo.rememberedCategory('27258805'))!.id, food);

      await repo.addTransaction(
          type: TxType.expense, money: Money(200, twd), categoryId: shop, note: 'Roti', invoiceNo: 'AA00000002', sellerNpwp: '27258805');
      s = (await repo.sellerFor('27258805'))!;
      expect(s.categoryId, shop, reason: 'kategori terakhir dipakai');
      expect(s.name, 'Kopi', reason: 'nama lama tidak ditimpa');
      expect((await db.select(db.sellers).get()).length, 1);
    });

    test('nama penjual diisi kemudian bila masih kosong dan catatan tidak kosong', () async {
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: food, invoiceNo: 'AA00000001', sellerNpwp: '11111111');
      expect((await repo.sellerFor('11111111'))!.name, isNull);
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: food, note: '  ', invoiceNo: 'AA00000002', sellerNpwp: '11111111');
      expect((await repo.sellerFor('11111111'))!.name, isNull);
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: food, note: 'Toko A', invoiceNo: 'AA00000003', sellerNpwp: '11111111');
      expect((await repo.sellerFor('11111111'))!.name, 'Toko A');
    });

    test('simpan atomik: faktur kembar membatalkan upsert penjual juga', () async {
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: food, invoiceNo: 'AA00000001');
      await expectLater(
          repo.addTransaction(
              type: TxType.expense, money: Money(100, twd), categoryId: shop, invoiceNo: 'AA00000001', sellerNpwp: '22222222'),
          throwsA(isA<DuplicateInvoiceException>()));
      expect(await repo.sellerFor('22222222'), isNull);
    });

    test('kategori terarsip atau bukan pengeluaran tidak diingat sebagai tebakan', () async {
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: shop, invoiceNo: 'AA00000001', sellerNpwp: '33333333');
      await repo.archiveCategory(shop);
      expect(await repo.rememberedCategory('33333333'), isNull);
      expect(await repo.rememberedCategory('99999999'), isNull);
    });

    test('hapus kategori ikut melupakan penjual; pindah transaksi memindahkan ingatan', () async {
      await repo.addTransaction(
          type: TxType.expense, money: Money(100, twd), categoryId: shop, invoiceNo: 'AA00000001', sellerNpwp: '44444444');
      await repo.moveTransactionsAndDelete(shop, food);
      expect((await repo.sellerFor('44444444'))!.categoryId, food);
      // kategori tanpa transaksi tetapi diingat penjual: hapus tidak melanggar kunci asing
      final cat = await repo.addCategory(name: 'Baru', icon: 'more', color: 1, type: TxType.expense);
      await db.into(db.sellers).insert(SellersCompanion.insert(npwp: '55555555', categoryId: cat, lastUsed: 1));
      await repo.deleteCategory(cat);
      expect(await repo.sellerFor('55555555'), isNull);
    });
  });

  group('CSV no_faktur', () {
    test('ekspor memuat kolom no_faktur dan round-trip persis', () {
      final rec = TxCsvRecord(
        occurredAt: DateTime.utc(2026, 11, 17, 4),
        type: TxType.expense,
        category: 'Belanja',
        amountMinor: 100,
        currency: twd,
        invoiceNo: 'HB35094463',
      );
      final csv = encodeTransactions([rec]);
      expect(csv.split('\r\n').first, endsWith(',no_faktur'));
      final back = parseTransactionCsv(csv);
      expect(back.errors, isEmpty);
      expect(back.records.single.invoiceNo, 'HB35094463');
    });

    test('berkas LAMA tanpa kolom no_faktur tetap terbaca (invoiceNo null)', () {
      final r = parseTransactionCsv(
          'Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan,Ikon,Warna\r\n2026-01-01T00:00:00Z,Keluar,A,1,IDR,,restaurant,#EF6C00\r\n');
      expect(r.errors, isEmpty);
      expect(r.records.single.invoiceNo, isNull);
    });

    test('impor: faktur yang sudah ada di DB dihitung duplikat; faktur kembar di dalam berkas hanya masuk sekali', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = Repository(db);
      final svc = ImportService(db);
      final food = (await repo.watchCategories(TxType.expense).first).first;
      await repo.addTransaction(
          type: TxType.expense,
          money: Money(100, twd),
          categoryId: food.id,
          occurredAt: DateTime.utc(2026, 11, 17, 4),
          invoiceNo: 'HB35094463');
      String line(String inv, String amount) =>
          '2026-11-20T10:00:00.000Z,Keluar,${food.name},$amount,TWD,,more,#000000,$inv\r\n';
      const head = 'Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan,Ikon,Warna,no_faktur\r\n';
      final parsed = parseTransactionCsv(
          '$head${line('HB35094463', '999')}${line('ZZ00000001', '5')}${line('ZZ00000001', '5')}${line('', '7')}${line('', '7')}');
      final plan = await svc.plan(parsed, ImportMode.merge);
      expect(plan.duplicates, 2, reason: 'HB... sudah ada di DB + ZZ... kedua');
      expect(plan.toInsert.length, 3, reason: 'ZZ sekali + dua baris tanpa faktur (multiset)');
      await svc.execute(plan);
      expect(await repo.countTransactions(), 4);
      // impor ulang berkas yang sama: tidak ada yang bertambah
      final again = await svc.plan(parsed, ImportMode.merge);
      expect(again.toInsert, isEmpty);

      // ganti semua: kembar dalam berkas tetap disaring (tidak melanggar indeks unik)
      final p2 = await svc.plan(parseTransactionCsv('$head${line('ZZ00000002', '5')}${line('ZZ00000002', '6')}'), ImportMode.replace);
      expect(p2.toInsert.length, 1);
      expect(p2.duplicates, 1);
    });

    test('ekspor dari DB membawa nomor faktur', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = Repository(db);
      final c = (await repo.watchCategories(TxType.expense).first).first;
      await repo.addTransaction(type: TxType.expense, money: Money(100, twd), categoryId: c.id, invoiceNo: 'HB35094463');
      final csv = buildCsv(await repo.rows(TxFilter.all));
      expect(csv, contains(',HB35094463'));
    });
  });
}
