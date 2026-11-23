import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/core/csv/transaction_csv.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/currency.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/features/transactions/data/csv_export.dart';
import 'package:myfinance/features/transactions/data/import_service.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');
  final jpy = currencyByCode('JPY');

  late AppDatabase src, dst;
  late Repository srcRepo, dstRepo;
  late Directory tmp;

  setUp(() {
    src = AppDatabase(NativeDatabase.memory());
    dst = AppDatabase(NativeDatabase.memory());
    srcRepo = Repository(src);
    dstRepo = Repository(dst);
    tmp = Directory.systemTemp.createTempSync('myfinance_imp');
  });
  tearDown(() async {
    await src.close();
    await dst.close();
    tmp.deleteSync(recursive: true);
  });

  /// Nama kembar dilarang: pakai kategori bawaan yang sama bila ada (ikon/warna disesuaikan).
  Future<int> cat(Repository r, String name, TxType t, {String icon = 'more', int color = 0xFF112233}) async {
    final all = await r.watchAllCategories().first;
    final hit = all.where((c) => categoryKey(c.type, c.name) == categoryKey(t, name)).firstOrNull;
    if (hit == null) return r.addCategory(name: name, icon: icon, color: color, type: t);
    await r.updateCategory(hit.id, icon: icon, color: color);
    return hit.id;
  }

  /// Semua kolom bermakna, urut stabil, untuk perbandingan persis.
  Future<List<String>> snapshot(Repository r) async {
    final rows = await r.rows(TxFilter.all);
    final l = [
      for (final x in rows)
        '${x.tx.occurredAt}|${x.tx.type.name}|${x.tx.amountMinor}|${x.tx.currencyCode}|${x.category.name}|${x.category.type.name}|${x.tx.note}'
    ]..sort();
    return l;
  }

  Future<TxCsvParseResult> exportParse(Repository r) async => parseTransactionCsv(buildCsv(await r.rows(TxFilter.all)));

  Future<ImportResult> doImport(AppDatabase db, TxCsvParseResult p, ImportMode m, {Directory? backup}) async {
    final s = ImportService(db, backupDir: backup ?? tmp);
    return s.execute(await s.plan(p, m));
  }

  Future<void> seedHard() async {
    final food = await cat(srcRepo, 'Makan & Minum', TxType.expense, icon: 'restaurant', color: 0xFFEF6C00);
    final odd = await cat(srcRepo, '=Aneh, "kutip"', TxType.expense, icon: 'gift', color: 0xFF00897B);
    final sal = await cat(srcRepo, 'Gaji', TxType.income, icon: 'salary', color: 0xFF43A047);
    Future<void> add(TxType t, int minor, cur, int c, DateTime at, String note) =>
        srcRepo.addTransaction(type: t, money: Money(minor, cur), categoryId: c, occurredAt: at, note: note);
    await add(TxType.expense, 18000, idr, food, DateTime(2026, 11, 18, 8, 5, 7, 123), 'Kopi, "enak"');
    await add(TxType.expense, 1250, usd, food, DateTime(2026, 11, 18, 23, 59, 59, 999), 'baris 1\nbaris 2');
    await add(TxType.expense, 500, jpy, odd, DateTime(2026, 11, 19, 0, 0, 0, 1), '=1+1');
    await add(TxType.expense, 1, idr, odd, DateTime(2026, 3, 29, 2, 30), '+62 812');
    await add(TxType.expense, 2, idr, odd, DateTime(2026, 1, 1, 0, 0), '-diskon');
    await add(TxType.expense, 3, idr, odd, DateTime(2026, 1, 1, 0, 0, 1), '@user');
    await add(TxType.expense, 4, idr, odd, DateTime(2026, 1, 1, 0, 0, 2), "'=sudah kutip");
    await add(TxType.expense, 5, idr, odd, DateTime(2026, 1, 1, 0, 0, 3), 'Jajan 🍜 日本語');
    await add(TxType.income, 999999999999999, usd, sal, DateTime(2025, 12, 31, 23, 59, 59), 'besar');
    await add(TxType.income, 5000000, idr, sal, DateTime.utc(2026, 6, 30, 17), '');
    // kembar persis (dua kopi di menit yang sama)
    await add(TxType.expense, 18000, idr, food, DateTime(2026, 5, 5, 10, 0, 0, 0), 'kembar');
    await add(TxType.expense, 18000, idr, food, DateTime(2026, 5, 5, 10, 0, 0, 0), 'kembar');
  }

  group('round-trip', () {
    test('ekspor -> impor ke DB kosong: SEMUA kolom identik (kategori ikut dibuat dengan ikon/warna)', () async {
      await seedHard();
      final before = await snapshot(srcRepo);
      final parsed = await exportParse(srcRepo);
      expect(parsed.errors, isEmpty);
      expect(parsed.records.length, before.length);

      final res = await doImport(dst, parsed, ImportMode.merge);
      expect(res.added, before.length);
      expect(res.skipped, 0);
      expect(await snapshot(dstRepo), before);

      // ikon & warna kategori ikut pulih
      final cats = await dstRepo.watchAllCategories().first;
      final odd = cats.firstWhere((c) => c.name == '=Aneh, "kutip"');
      expect(odd.icon, 'gift');
      expect(odd.color, 0xFF00897B);
    });

    test('tanggal sekitar pergantian hari tetap pada detik yang sama', () async {
      await seedHard();
      final parsed = await exportParse(srcRepo);
      await doImport(dst, parsed, ImportMode.merge);
      final a = await srcRepo.rows(TxFilter.all);
      final b = await dstRepo.rows(TxFilter.all);
      expect(b.map((e) => e.tx.occurredAt).toSet(), a.map((e) => e.tx.occurredAt).toSet());
    });
  });

  group('deduplikasi (multiset)', () {
    test('impor berkas yang sama dua kali: tidak ada data ganda', () async {
      await seedHard();
      final parsed = await exportParse(srcRepo);
      await doImport(dst, parsed, ImportMode.merge);
      final once = await snapshot(dstRepo);
      final r2 = await doImport(dst, parsed, ImportMode.merge);
      expect(r2.added, 0);
      expect(r2.skipped, parsed.records.length);
      expect(await snapshot(dstRepo), once);
    });

    test('tumpang tindih sebagian: hanya yang baru masuk', () async {
      await seedHard();
      final parsed = await exportParse(srcRepo);
      // DB tujuan sudah punya 4 transaksi pertama dari berkas
      final partial = TxCsvParseResult(records: parsed.records.take(4).toList());
      await doImport(dst, partial, ImportMode.merge);
      final r = await doImport(dst, parsed, ImportMode.merge);
      expect(r.skipped, 4);
      expect(r.added, parsed.records.length - 4);
      expect(await snapshot(dstRepo), await snapshot(srcRepo));
    });

    test('dua transaksi kembar tetap dua; 2 di berkas + 1 di DB -> tambah 1', () async {
      final f = await cat(dstRepo, 'Makan', TxType.expense);
      final at = DateTime(2026, 5, 5, 10);
      await dstRepo.addTransaction(type: TxType.expense, money: Money(100, idr), categoryId: f, occurredAt: at, note: 'k');
      final rec = TxCsvRecord(occurredAt: at, type: TxType.expense, category: 'makan', amountMinor: 100, currency: idr, note: 'k');
      final s = ImportService(dst, backupDir: tmp);
      final plan = await s.plan(TxCsvParseResult(records: [rec, rec]), ImportMode.merge);
      expect(plan.duplicates, 1);
      expect(plan.toInsert.length, 1);
      await s.execute(plan);
      expect((await dstRepo.rows(TxFilter.all)).length, 2);
      // kategori cocok tanpa peka huruf: tidak membuat duplikat
      expect((await dstRepo.watchAllCategories().first).where((c) => c.name.toLowerCase() == 'makan').length, 1);
    });

    test('kembar di berkas, DB kosong: keduanya masuk', () async {
      final at = DateTime(2026, 5, 5, 10);
      final rec = TxCsvRecord(occurredAt: at, type: TxType.expense, category: 'X', amountMinor: 1, currency: idr);
      final r = await doImport(dst, TxCsvParseResult(records: [rec, rec]), ImportMode.merge);
      expect(r.added, 2);
    });

    test('berkas ekspor LAMA (menit, tanpa zona) cocok dengan data yang sudah ada per menit', () async {
      final f = await cat(dstRepo, 'Makan', TxType.expense);
      await dstRepo.addTransaction(
          type: TxType.expense, money: Money(1250, usd), categoryId: f, occurredAt: DateTime(2026, 11, 18, 8, 5, 37), note: 'kopi');
      final old = parseTransactionCsv('Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan\r\n'
          '2026-11-18 08:05,Keluar,Makan,12.50,USD,kopi\r\n'
          '2026-11-18 09:00,Keluar,Makan,3.00,USD,baru\r\n');
      expect(old.errors, isEmpty);
      final r = await doImport(dst, old, ImportMode.merge);
      expect(r.skipped, 1);
      expect(r.added, 1);
    });
  });

  group('pratinjau (plan) tidak menulis apa pun', () {
    test('menghitung valid/duplikat/galat/kategori baru/rentang/total per mata uang', () async {
      final f = await cat(dstRepo, 'Makan', TxType.expense);
      await dstRepo.addTransaction(
          type: TxType.expense, money: Money(100, idr), categoryId: f, occurredAt: DateTime.utc(2026, 1, 1), note: '');
      final p = parseTransactionCsv('Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan\n'
          '2026-01-01T00:00:00Z,Keluar,Makan,100,IDR,\n' //   duplikat
          '2026-02-01T00:00:00Z,Keluar,Baru,200,IDR,\n' //    kategori baru
          '2026-03-01T00:00:00Z,Masuk,Baru,5.50,USD,\n' //    kategori baru (jenis lain)
          '2026-03-02T00:00:00Z,Masuk,Baru,3.00,USD,\n'
          'rusak,Masuk,Baru,1,IDR,\n');
      final plan = await ImportService(dst, backupDir: tmp).plan(p, ImportMode.merge);
      expect(plan.toInsert.length, 3);
      expect(plan.duplicates, 1);
      expect(plan.errors.length, 1);
      expect(plan.newCategories.map((c) => '${c.type.name}:${c.name}').toSet(), {'expense:Baru', 'income:Baru'});
      expect(plan.from, DateTime.utc(2026, 1, 1).toLocal());
      expect(plan.to, DateTime.utc(2026, 3, 2).toLocal());
      // total per mata uang: tidak dijumlah silang
      final usdT = plan.totals.firstWhere((t) => t.currency == usd);
      final idrT = plan.totals.firstWhere((t) => t.currency == idr);
      expect(usdT.incomeMinor, 850);
      expect(idrT.expenseMinor, 200);
      expect(plan.totals.length, 2);
      expect((await dstRepo.rows(TxFilter.all)).length, 1, reason: 'belum menulis');
      expect((await dstRepo.watchAllCategories().first).any((c) => c.name == 'Baru'), isFalse);
    });

    test('kategori terarsip yang cocok dipakai kembali (bukan kategori baru)', () async {
      final f = await cat(dstRepo, 'Lama', TxType.expense);
      await dstRepo.archiveCategory(f);
      final rec = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 1), type: TxType.expense, category: ' lama ', amountMinor: 1, currency: idr);
      final s = ImportService(dst, backupDir: tmp);
      final plan = await s.plan(TxCsvParseResult(records: [rec]), ImportMode.merge);
      expect(plan.newCategories, isEmpty);
      await s.execute(plan);
      final all = await dstRepo.watchAllCategories().first;
      expect(all.where((c) => c.name.toLowerCase() == 'lama').length, 1);
      expect((await dstRepo.rows(TxFilter.all)).single.category.id, f);
    });
  });

  group('mode Ganti semua', () {
    test('membuat cadangan CSV sebelum menghapus, lalu mengisi dari berkas', () async {
      await seedHard();
      final snapSrc = await snapshot(srcRepo);
      final f = await cat(dstRepo, 'Punya Lama', TxType.expense);
      await dstRepo.addTransaction(type: TxType.expense, money: Money(777, idr), categoryId: f, note: 'lama sekali');
      final backup = Directory('${tmp.path}/backups');

      final res = await doImport(dst, await exportParse(srcRepo), ImportMode.replace, backup: backup);
      expect(res.backupPath, isNotNull);
      expect(await snapshot(dstRepo), snapSrc, reason: 'data lama hilang, isi = berkas');

      final bk = File(res.backupPath!);
      expect(bk.existsSync(), isTrue);
      final restored = parseTransactionCsv(await bk.readAsString());
      expect(restored.records.single.note, 'lama sekali');
      expect(restored.records.single.amountMinor, 777);
      // kategori lama tidak dihapus
      expect((await dstRepo.watchAllCategories().first).any((c) => c.name == 'Punya Lama'), isTrue);
    });

    test('kegagalan di tengah jalan: SELURUH transaksi dibatalkan, data lama utuh, cadangan tetap ada', () async {
      final f = await cat(dstRepo, 'Aman', TxType.expense);
      for (var i = 0; i < 3; i++) {
        await dstRepo.addTransaction(type: TxType.expense, money: Money(100 + i, idr), categoryId: f, note: 'lama$i');
      }
      final before = await snapshot(dstRepo);
      final good = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 1), type: TxType.expense, category: 'Baru', amountMinor: 1, currency: idr);
      // kode mata uang 4 huruf melanggar CHECK di SQL -> insert gagal di tengah batch
      final bad = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 2), type: TxType.expense, category: 'Baru', amountMinor: 1, currency: const Currency4('IDRX'));
      final s = ImportService(dst, backupDir: Directory('${tmp.path}/bk'));
      final plan = ImportPlan(
        mode: ImportMode.replace,
        toInsert: [good, good, bad],
        duplicates: 0,
        errors: const [],
        newCategories: const [],
        from: null,
        to: null,
        totals: const [],
      );
      await expectLater(s.execute(plan, chunk: 2), throwsA(anything));
      expect(await snapshot(dstRepo), before, reason: 'rollback penuh');
      expect((await dstRepo.watchAllCategories().first).any((c) => c.name == 'Baru'), isFalse, reason: 'kategori baru ikut dibatalkan');
      final backups = Directory('${tmp.path}/bk').listSync();
      expect(backups.length, 1, reason: 'cadangan dibuat sebelum penghapusan');
    });

    test('mode Gabungkan yang gagal juga atomik', () async {
      final bad = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 2), type: TxType.expense, category: 'Z', amountMinor: 1, currency: const Currency4('IDRX'));
      final good = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 1), type: TxType.expense, category: 'Z', amountMinor: 1, currency: idr);
      final plan = ImportPlan(mode: ImportMode.merge, toInsert: [good, bad], duplicates: 0, errors: const [], newCategories: const [], from: null, to: null, totals: const []);
      await expectLater(ImportService(dst, backupDir: tmp).execute(plan, chunk: 1), throwsA(anything));
      expect((await dstRepo.rows(TxFilter.all)), isEmpty);
    });
  });

  test('tidak menyentuh pengaturan/kategori yang tak terkait; kategori baru diurut di akhir', () async {
    final before = (await dstRepo.watchCategories(TxType.expense).first).length;
    final rec = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 1), type: TxType.expense, category: 'Baru A', amountMinor: 1, currency: idr);
    final rec2 = TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 2), type: TxType.expense, category: 'Baru B', amountMinor: 1, currency: idr);
    await doImport(dst, TxCsvParseResult(records: [rec, rec2]), ImportMode.merge);
    final l = await dstRepo.watchCategories(TxType.expense).first;
    expect(l.length, before + 2);
    expect(l.map((c) => c.name).toList().sublist(before), ['Baru A', 'Baru B']);
  });

  test('KINERJA: 10.000 baris -> ekspor, parse, plan, impor', () async {
    final c = await cat(srcRepo, 'Perf', TxType.expense);
    final base = DateTime(2024, 1, 1);
    await src.batch((b) {
      for (var i = 0; i < 10000; i++) {
        b.insert(
            src.transactions,
            TransactionsCompanion.insert(
              type: TxType.expense,
              amountMinor: 1000 + i,
              currencyCode: i % 10 == 0 ? 'USD' : 'IDR',
              categoryId: c,
              note: Value('catatan, ke-$i'),
              occurredAt: base.add(Duration(minutes: i * 7)).toUtc().millisecondsSinceEpoch,
              createdAt: 0,
              updatedAt: 0,
            ));
      }
    });
    final sw = Stopwatch()..start();
    final csv = buildCsv(await srcRepo.rows(TxFilter.all));
    final tExport = sw.elapsedMilliseconds;
    sw.reset();
    final parsed = parseTransactionCsv(csv);
    final tParse = sw.elapsedMilliseconds;
    expect(parsed.errors, isEmpty);
    expect(parsed.records.length, 10000);
    final s = ImportService(dst, backupDir: tmp);
    sw.reset();
    final plan = await s.plan(parsed, ImportMode.merge);
    final tPlan = sw.elapsedMilliseconds;
    sw.reset();
    final res = await s.execute(plan);
    final tWrite = sw.elapsedMilliseconds;
    expect(res.added, 10000);
    sw.reset();
    final plan2 = await s.plan(parsed, ImportMode.merge); // impor ulang: semua duplikat
    final tReplan = sw.elapsedMilliseconds;
    expect(plan2.duplicates, 10000);
    expect(plan2.toInsert, isEmpty);
    // ignore: avoid_print
    print('PERF-IMPORT export=${tExport}ms parse=${tParse}ms plan=${tPlan}ms write=${tWrite}ms replan(dedup 10k)=${tReplan}ms');
    expect(tParse, lessThan(3000));
    expect(tWrite, lessThan(10000));
  });
}

/// Mata uang "palsu" 4 huruf untuk memicu kegagalan SQL (CHECK length = 3) di tengah penulisan.
class Currency4 implements Currency {
  @override
  final String code;
  const Currency4(this.code);
  @override
  String get symbol => code;
  @override
  int get decimals => 0;
  @override
  String get name => code;
}
