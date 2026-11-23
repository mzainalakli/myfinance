import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final idr = currencyByCode('IDR');
  late AppDatabase db;
  late Repository repo;
  late Category food, transport, other, salary;

  Future<Category> byName(String n, TxType t) async =>
      (await repo.watchAllCategories().first).firstWhere((c) => c.name == n && c.type == t);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    food = await byName('Makan & Minum', TxType.expense);
    transport = await byName('Transportasi', TxType.expense);
    other = await byName('Lainnya', TxType.expense);
    salary = await byName('Gaji', TxType.income);
  });
  tearDown(() => db.close());

  Future<void> tx(int cat, {TxType t = TxType.expense}) =>
      repo.addTransaction(type: t, money: Money(1000, idr), categoryId: cat).then((_) {});

  Future<Category> get(int id) async => (await repo.watchAllCategories().first).firstWhere((c) => c.id == id);
  Future<void> expectError(Future<void> f, CategoryError e) => expectLater(
      f, throwsA(isA<CategoryException>().having((x) => x.error, 'error', e)));

  group('edit', () {
    test('nama, ikon, warna berubah; transaksi lama ikut (referensi id)', () async {
      await tx(food.id);
      await repo.updateCategory(food.id, name: '  Makanan ', icon: 'coffee', color: 0xFF112233);
      final c = await get(food.id);
      expect([c.name, c.icon, c.color], ['Makanan', 'coffee', 0xFF112233]);
      final rows = await repo.rows(TxFilter.all);
      expect(rows.single.category.name, 'Makanan');
    });
    test('validasi nama: kosong, terlalu panjang, kembar (huruf besar/kecil, spasi, terarsip)', () async {
      await expectError(repo.updateCategory(food.id, name: '   '), CategoryError.emptyName);
      await expectError(repo.updateCategory(food.id, name: 'x' * 41), CategoryError.nameTooLong);
      await expectError(repo.updateCategory(food.id, name: '  transportasi '), CategoryError.duplicateName);
      await expectError(repo.addCategory(name: 'BELANJA', icon: 'more', color: 1, type: TxType.expense),
          CategoryError.duplicateName);
      // jenis berbeda boleh sama
      await repo.addCategory(name: 'Belanja', icon: 'more', color: 1, type: TxType.income);
      // kategori terarsip tetap menghalangi
      await repo.archiveCategory(transport.id);
      await expectError(repo.updateCategory(food.id, name: 'Transportasi'), CategoryError.duplicateName);
      // nama sendiri (ganti huruf besar) boleh
      await repo.updateCategory(food.id, name: 'makan & minum');
    });
    test('jenis terkunci bila dipakai; boleh bila belum dipakai', () async {
      await tx(food.id);
      await expectError(repo.updateCategory(food.id, type: TxType.income), CategoryError.typeLocked);
      await repo.updateCategory(transport.id, type: TxType.income);
      final c = await get(transport.id);
      expect(c.type, TxType.income);
      final inc = (await repo.watchCategories(TxType.income).first);
      expect(inc.last.id, transport.id, reason: 'masuk di akhir urutan jenis baru');
    });
    test('kategori bawaan tidak terkunci', () async {
      expect(food.name, 'Makan & Minum');
      await repo.updateCategory(food.id, name: 'Jajan');
      await repo.updateCategory(other.id, name: 'Misc');
    });
  });

  group('hapus', () {
    test('tanpa transaksi: hapus permanen, bisa diurungkan', () async {
      final d = await repo.deleteCategory(transport.id);
      expect((await repo.watchAllCategories().first).any((c) => c.id == transport.id), isFalse);
      await repo.restoreCategory(d);
      expect((await get(transport.id)).name, 'Transportasi');
    });
    test('dengan transaksi: ditolak (tidak menghapus transaksi)', () async {
      await tx(food.id);
      await expectError(repo.deleteCategory(food.id), CategoryError.hasTransactions);
      expect(await repo.countTransactions(), 1);
    });
    test('pindahkan: transaksi + templat pindah, kategori hilang', () async {
      await tx(food.id);
      await tx(food.id);
      await db.into(db.templates).insert(TemplatesCompanion.insert(
          categoryId: food.id, amountMinor: 5000, currencyCode: 'IDR'));
      final n = await repo.moveTransactionsAndDelete(food.id, transport.id);
      expect(n, 2);
      expect(await repo.categoryTransactionCount(transport.id), 2);
      expect((await db.select(db.templates).get()).single.categoryId, transport.id);
      expect((await repo.watchAllCategories().first).any((c) => c.id == food.id), isFalse);
      expect(await repo.countTransactions(), 2);
    });
    test('pindah: tujuan harus sejenis, aktif, dan bukan diri sendiri', () async {
      await tx(food.id);
      await expectError(repo.moveTransactionsAndDelete(food.id, salary.id), CategoryError.invalidTarget);
      await expectError(repo.moveTransactionsAndDelete(food.id, food.id), CategoryError.invalidTarget);
      await repo.archiveCategory(transport.id);
      await expectError(repo.moveTransactionsAndDelete(food.id, transport.id), CategoryError.invalidTarget);
    });
    test('pindah atomik: gagal di tengah -> semua dibatalkan', () async {
      await tx(food.id);
      await db.into(db.templates).insert(TemplatesCompanion.insert(
          categoryId: food.id, amountMinor: 5000, currencyCode: 'IDR'));
      await expectLater(
        repo.moveTransactionsAndDelete(food.id, transport.id, debugFailAfterMove: () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await repo.categoryTransactionCount(food.id), 1);
      expect(await repo.categoryTransactionCount(transport.id), 0);
      expect((await db.select(db.templates).get()).single.categoryId, food.id);
      expect((await get(food.id)).name, 'Makan & Minum');
    });
    test('templat tanpa transaksi ikut terhapus saat kategori dihapus (tidak ada rujukan menggantung)', () async {
      await db.into(db.templates).insert(TemplatesCompanion.insert(
          categoryId: transport.id, amountMinor: 5000, currencyCode: 'IDR'));
      await repo.deleteCategory(transport.id);
      expect(await db.select(db.templates).get(), isEmpty);
    });
  });

  group('arsip', () {
    test('arsip menyembunyikan dari pemilih, transaksi lama utuh, bisa dipulihkan', () async {
      await tx(food.id);
      await repo.archiveCategory(food.id);
      expect((await repo.watchCategories(TxType.expense).first).any((c) => c.id == food.id), isFalse);
      expect((await repo.watchCategoriesByUsage(TxType.expense).first).any((c) => c.id == food.id), isFalse);
      final rows = await repo.rows(TxFilter.all);
      expect(rows.single.category.name, 'Makan & Minum');
      await repo.unarchiveCategory(food.id);
      expect((await repo.watchCategories(TxType.expense).first).any((c) => c.id == food.id), isTrue);
    });
    test('kategori aktif terakhir per jenis tidak bisa dihapus/diarsipkan/dipindah jenis', () async {
      final inc = await repo.watchCategories(TxType.income).first;
      for (final c in inc.skip(1)) {
        await repo.deleteCategory(c.id);
      }
      await expectError(repo.deleteCategory(salary.id), CategoryError.lastOfType);
      await expectError(repo.archiveCategory(salary.id), CategoryError.lastOfType);
      await expectError(repo.updateCategory(salary.id, type: TxType.expense), CategoryError.lastOfType);
      // jenis lain tidak terpengaruh
      await repo.deleteCategory(transport.id);
    });
    test('kategori terarsip tidak dihitung sebagai pemilih', () async {
      final exp = await repo.watchCategories(TxType.expense).first;
      for (final c in exp.skip(1)) {
        await repo.archiveCategory(c.id);
      }
      await expectError(repo.archiveCategory(exp.first.id), CategoryError.lastOfType);
    });
  });

  test('urutan tersimpan', () async {
    final ids = (await repo.watchCategories(TxType.expense).first).map((c) => c.id).toList();
    ids.insert(0, ids.removeLast());
    await repo.reorderCategories(ids);
    expect((await repo.watchCategories(TxType.expense).first).map((c) => c.id).toList(), ids);
  });

  test('jumlah transaksi per kategori', () async {
    await tx(food.id);
    await tx(food.id);
    await tx(salary.id, t: TxType.income);
    final m = await repo.watchCategoryCounts().first;
    expect(m[food.id], 2);
    expect(m[salary.id], 1);
    expect(m[transport.id], isNull);
  });

  test('impor memakai ulang kategori terarsip (kunci sama), tanpa duplikat', () async {
    expect(categoryKey(TxType.expense, ' Makan & MINUM '), categoryKey(TxType.expense, 'makan & minum'));
    await repo.archiveCategory(food.id);
    // aturan impor (_catKey) = categoryKey; kategori terarsip ikut dalam pencarian (select semua)
    final all = await db.select(db.categories).get();
    expect(all.any((c) => categoryKey(c.type, c.name) == categoryKey(TxType.expense, 'MAKAN & MINUM')), isTrue);
  });
}
