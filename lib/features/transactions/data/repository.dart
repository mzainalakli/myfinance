import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/money/money.dart';
import '../../../core/util/dates.dart';
import 'summary.dart';
import 'tx_filter.dart';

const kCategoryNameMax = 40;

/// Kunci pencocokan kategori: dipakai validasi nama kembar DAN impor CSV (satu aturan).
String categoryKey(TxType t, String name) => '${t.name}|${name.trim().toLowerCase()}';

enum CategoryError { emptyName, nameTooLong, duplicateName, typeLocked, lastOfType, hasTransactions, invalidTarget, notFound }

class CategoryException implements Exception {
  final CategoryError error;
  const CategoryException(this.error);
  @override
  String toString() => 'CategoryException($error)';
}

/// Faktur dengan nomor ini sudah tercatat ([existing]).
class DuplicateInvoiceException implements Exception {
  final Transaction existing;
  const DuplicateInvoiceException(this.existing);
  @override
  String toString() => 'DuplicateInvoiceException(${existing.invoiceNo})';
}

class DeletedCategory {
  final Category category;
  final List<Template> templates;
  const DeletedCategory(this.category, this.templates);
}

/// Satu-satunya lapisan akses data. Aplikasi utama dan popup memakainya.
class Repository {
  final AppDatabase db;
  Repository(this.db);

  // ---------- transaksi ----------

  Expression<bool> _predicate(TxFilter f, DateTime now) {
    final t = db.transactions;
    Expression<bool> p = const Constant(true);
    final r = f.resolveRange(now);
    if (r != null) {
      p = p &
          t.occurredAt.isBiggerOrEqualValue(toEpochMs(r.start)) &
          t.occurredAt.isSmallerThanValue(toEpochMs(r.endExclusive));
    }
    if (f.categoryIds.isNotEmpty) p = p & t.categoryId.isIn(f.categoryIds);
    if (f.type != null) p = p & t.type.equalsValue(f.type!);
    if (f.currencies.isNotEmpty) p = p & t.currencyCode.isIn(f.currencies);
    final q = f.query.trim();
    if (q.isNotEmpty) {
      // % dan _ diperlakukan sebagai huruf biasa; LIKE SQLite tak peka huruf (ASCII).
      final esc = q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      p = p & t.note.like('%$esc%', escapeChar: r'\');
    }
    return p;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _rowsQuery(TxFilter f, DateTime now, {int? limit}) {
    final q = (db.select(db.transactions).join([
      innerJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
    ])
      ..where(_predicate(f, now))
      ..orderBy([
        OrderingTerm.desc(db.transactions.occurredAt),
        OrderingTerm.desc(db.transactions.id),
      ]));
    if (limit != null) q.limit(limit);
    return q;
  }

  TxRow _toRow(TypedResult r) => TxRow(r.readTable(db.transactions), r.readTable(db.categories));

  Stream<List<TxRow>> watchRows(TxFilter f, {DateTime? now, int? limit}) =>
      _rowsQuery(f, now ?? DateTime.now(), limit: limit).watch().map((l) => l.map(_toRow).toList());

  Future<List<TxRow>> rows(TxFilter f, {DateTime? now}) async =>
      (await _rowsQuery(f, now ?? DateTime.now()).get()).map(_toRow).toList();

  /// [invoiceNo]: nomor faktur elektronik (unik). [sellerNpwp]: bila diberikan, ingatan penjual diperbarui
  /// dalam transaksi DB yang sama (kategori terakhir dipakai; nama hanya bila masih kosong dan [note] tidak kosong).
  Future<int> addTransaction({
    required TxType type,
    required Money money,
    required int categoryId,
    String note = '',
    DateTime? occurredAt,
    DateTime? now,
    String? invoiceNo,
    String? sellerNpwp,
  }) =>
      db.transaction(() async {
        final nowDt = now ?? DateTime.now();
        final n = toEpochMs(nowDt);
        if (invoiceNo != null) {
          final dup = await findByInvoice(invoiceNo);
          if (dup != null) throw DuplicateInvoiceException(dup);
        }
        final id = await db.into(db.transactions).insert(TransactionsCompanion.insert(
              type: type,
              amountMinor: money.minor,
              currencyCode: money.currency.code,
              categoryId: categoryId,
              note: Value(note.trim()),
              occurredAt: occurredAt == null ? n : toEpochMs(occurredAt),
              createdAt: n,
              updatedAt: n,
              invoiceNo: Value(invoiceNo),
            ));
        if (sellerNpwp != null) await _upsertSeller(sellerNpwp, categoryId, note.trim(), n);
        return id;
      });

  Future<TxRow?> rowById(int id) async {
    final r = await (db.select(db.transactions).join([
      innerJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
    ])
          ..where(db.transactions.id.equals(id)))
        .getSingleOrNull();
    return r == null ? null : _toRow(r);
  }

  Future<Transaction?> findByInvoice(String invoiceNo) =>
      (db.select(db.transactions)..where((t) => t.invoiceNo.equals(invoiceNo))).getSingleOrNull();

  // ---------- penjual (ingatan faktur) ----------

  Future<Seller?> sellerFor(String npwp) =>
      (db.select(db.sellers)..where((s) => s.npwp.equals(npwp))).getSingleOrNull();

  /// Kategori yang diingat untuk penjual ini, hanya bila masih ada, aktif, dan berjenis pengeluaran.
  Future<Category?> rememberedCategory(String npwp) async {
    final s = await sellerFor(npwp);
    if (s == null) return null;
    final c = await (db.select(db.categories)..where((c) => c.id.equals(s.categoryId))).getSingleOrNull();
    return (c == null || c.isArchived || c.type != TxType.expense) ? null : c;
  }

  Future<void> _upsertSeller(String npwp, int categoryId, String note, int nowMs) async {
    final cur = await sellerFor(npwp);
    if (cur == null) {
      await db.into(db.sellers).insert(SellersCompanion.insert(
            npwp: npwp,
            name: Value(note.isEmpty ? null : note),
            categoryId: categoryId,
            lastUsed: nowMs,
          ));
    } else {
      final keepName = cur.name != null && cur.name!.isNotEmpty;
      await (db.update(db.sellers)..where((s) => s.npwp.equals(npwp))).write(SellersCompanion(
        categoryId: Value(categoryId),
        lastUsed: Value(nowMs),
        name: keepName || note.isEmpty ? const Value.absent() : Value(note),
      ));
    }
  }

  Future<void> updateTransaction(
    int id, {
    required TxType type,
    required Money money,
    required int categoryId,
    required String note,
    required DateTime occurredAt,
  }) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: Value(type),
        amountMinor: Value(money.minor),
        currencyCode: Value(money.currency.code),
        categoryId: Value(categoryId),
        note: Value(note.trim()),
        occurredAt: Value(toEpochMs(occurredAt)),
        updatedAt: Value(toEpochMs(DateTime.now())),
      ),
    );
  }

  Future<void> deleteTransaction(int id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  /// Untuk "urungkan hapus": masukkan kembali baris yang sama (id sama).
  Future<void> restoreTransaction(Transaction t) =>
      db.into(db.transactions).insert(t, mode: InsertMode.insertOrReplace);

  Future<int> countTransactions() async {
    final c = db.transactions.id.count();
    return (await (db.selectOnly(db.transactions)..addColumns([c])).map((r) => r.read(c)).getSingle()) ?? 0;
  }

  // ---------- kategori ----------

  Stream<List<Category>> watchCategories(TxType type, {bool includeArchived = false}) {
    final q = db.select(db.categories)
      ..where((c) => c.type.equalsValue(type) & (includeArchived ? const Constant(true) : c.isArchived.equals(false)))
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]);
    return q.watch();
  }

  Stream<List<Category>> watchAllCategories() {
    final q = db.select(db.categories)..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]);
    return q.watch();
  }

  /// Kategori aktif, yang paling sering dipakai di depan.
  Stream<List<Category>> watchCategoriesByUsage(TxType type) {
    return db
        .customSelect(
          'SELECT c.*, COUNT(t.id) AS uses FROM categories c '
          'LEFT JOIN transactions t ON t.category_id = c.id '
          'WHERE c.type = ?1 AND c.is_archived = 0 '
          'GROUP BY c.id ORDER BY uses DESC, c.sort_order ASC, c.id ASC',
          variables: [Variable.withString(type.name)],
          readsFrom: {db.categories, db.transactions},
        )
        .watch()
        .map((rows) => rows.map((r) => db.categories.map(r.data)).toList());
  }

  /// Jumlah transaksi per kategori (id -> jumlah). Kategori tanpa transaksi tidak ada di peta.
  Stream<Map<int, int>> watchCategoryCounts() => db
      .customSelect('SELECT category_id AS id, COUNT(*) AS n FROM transactions GROUP BY category_id',
          readsFrom: {db.transactions})
      .watch()
      .map((rows) => {for (final r in rows) r.read<int>('id'): r.read<int>('n')});

  Future<int> categoryTransactionCount(int id) async {
    final c = db.transactions.id.count();
    return (await (db.selectOnly(db.transactions)
              ..addColumns([c])
              ..where(db.transactions.categoryId.equals(id)))
            .map((r) => r.read(c))
            .getSingle()) ??
        0;
  }

  Future<int> _templateCount(int id) async {
    final c = db.templates.id.count();
    return (await (db.selectOnly(db.templates)
              ..addColumns([c])
              ..where(db.templates.categoryId.equals(id)))
            .map((r) => r.read(c))
            .getSingle()) ??
        0;
  }

  Future<Category> _category(int id) async {
    final c = await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
    if (c == null) throw const CategoryException(CategoryError.notFound);
    return c;
  }

  /// Nama valid: tidak kosong, maks [kCategoryNameMax], tidak kembar (jenis sama, huruf besar/kecil dan
  /// spasi pinggir diabaikan, kategori terarsip ikut dihitung) dengan kategori lain. Aturan kunci sama dengan impor.
  Future<String> _validName(String raw, TxType type, {int? exceptId}) async {
    final n = raw.trim();
    if (n.isEmpty) throw const CategoryException(CategoryError.emptyName);
    if (n.length > kCategoryNameMax) throw const CategoryException(CategoryError.nameTooLong);
    final key = categoryKey(type, n);
    final all = await db.select(db.categories).get();
    if (all.any((c) => c.id != exceptId && categoryKey(c.type, c.name) == key)) {
      throw const CategoryException(CategoryError.duplicateName);
    }
    return n;
  }

  Future<int> _activeCount(TxType type, {int? exceptId}) async {
    final all = await (db.select(db.categories)
          ..where((c) => c.type.equalsValue(type) & c.isArchived.equals(false)))
        .get();
    return all.where((c) => c.id != exceptId).length;
  }

  /// Menghapus/mengarsipkan/memindah jenis kategori aktif tidak boleh menyisakan jenis itu tanpa pemilih.
  Future<void> _ensureNotLast(Category c) async {
    if (!c.isArchived && await _activeCount(c.type, exceptId: c.id) == 0) {
      throw const CategoryException(CategoryError.lastOfType);
    }
  }

  /// True bila [c] adalah satu-satunya kategori aktif untuk jenisnya (tidak boleh dihapus/diarsipkan).
  Future<bool> isLastActive(Category c) async => !c.isArchived && await _activeCount(c.type, exceptId: c.id) == 0;

  Future<int> _nextOrder(TxType type) async {
    final maxOrder = await (db.selectOnly(db.categories)
          ..addColumns([db.categories.sortOrder.max()])
          ..where(db.categories.type.equalsValue(type)))
        .map((r) => r.read(db.categories.sortOrder.max()))
        .getSingle();
    return (maxOrder ?? -1) + 1;
  }

  Future<int> addCategory({
    required String name,
    required String icon,
    required int color,
    required TxType type,
  }) =>
      db.transaction(() async {
        final n = await _validName(name, type);
        return db.into(db.categories).insert(CategoriesCompanion.insert(
              name: n, icon: icon, color: color, type: type,
              sortOrder: Value(await _nextOrder(type)),
            ));
      });

  /// Ubah nama/ikon/warna/jenis. Jenis hanya boleh berubah bila kategori belum dipakai transaksi
  /// (atau templat). Transaksi menyimpan id, jadi mengganti nama langsung berlaku di semua transaksi lama.
  Future<void> updateCategory(int id, {String? name, String? icon, int? color, TxType? type}) =>
      db.transaction(() async {
        final cur = await _category(id);
        final newType = type ?? cur.type;
        final changeType = newType != cur.type;
        if (changeType) {
          if (await categoryTransactionCount(id) > 0 || await _templateCount(id) > 0) {
            throw const CategoryException(CategoryError.typeLocked);
          }
          await _ensureNotLast(cur);
        }
        final n = (name == null && !changeType) ? null : await _validName(name ?? cur.name, newType, exceptId: id);
        await (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
          name: n == null ? const Value.absent() : Value(n),
          icon: icon == null ? const Value.absent() : Value(icon),
          color: color == null ? const Value.absent() : Value(color),
          type: changeType ? Value(newType) : const Value.absent(),
          sortOrder: changeType ? Value(await _nextOrder(newType)) : const Value.absent(),
        ));
      });

  /// Arsip: hilang dari pemilih dan daftar utama; transaksi lama utuh. Tidak boleh pada kategori aktif terakhir sejenis.
  Future<void> archiveCategory(int id) => db.transaction(() async {
        final c = await _category(id);
        await _ensureNotLast(c);
        await (db.update(db.categories)..where((x) => x.id.equals(id)))
            .write(const CategoriesCompanion(isArchived: Value(true)));
      });

  Future<void> unarchiveCategory(int id) => (db.update(db.categories)..where((c) => c.id.equals(id)))
      .write(const CategoriesCompanion(isArchived: Value(false)));

  /// Hapus permanen kategori TANPA transaksi (templat yang merujuk ikut dihapus). Mengembalikan salinan untuk Urungkan.
  Future<DeletedCategory> deleteCategory(int id) => db.transaction(() async {
        final c = await _category(id);
        if (await categoryTransactionCount(id) > 0) throw const CategoryException(CategoryError.hasTransactions);
        await _ensureNotLast(c);
        final tpls = await (db.select(db.templates)..where((t) => t.categoryId.equals(id))).get();
        await (db.delete(db.templates)..where((t) => t.categoryId.equals(id))).go();
        // ingatan penjual yang menunjuk kategori ini ikut dilupakan (kategori sudah tak ada)
        await (db.delete(db.sellers)..where((x) => x.categoryId.equals(id))).go();
        await (db.delete(db.categories)..where((x) => x.id.equals(id))).go();
        return DeletedCategory(c, tpls);
      });

  Future<void> restoreCategory(DeletedCategory d) => db.transaction(() async {
        await db.into(db.categories).insert(d.category, mode: InsertMode.insertOrReplace);
        for (final t in d.templates) {
          await db.into(db.templates).insert(t, mode: InsertMode.insertOrReplace);
        }
      });

  /// Pindahkan semua transaksi (dan templat) ke [targetId] lalu hapus kategori, dalam satu transaksi DB.
  /// Tujuan harus kategori aktif berjenis sama. [debugFailAfterMove] hanya untuk menguji rollback.
  Future<int> moveTransactionsAndDelete(int id, int targetId, {Future<void> Function()? debugFailAfterMove}) =>
      db.transaction(() async {
        final c = await _category(id);
        final target = await _category(targetId);
        if (id == targetId || target.type != c.type || target.isArchived) {
          throw const CategoryException(CategoryError.invalidTarget);
        }
        final moved = await categoryTransactionCount(id);
        await (db.update(db.transactions)..where((t) => t.categoryId.equals(id)))
            .write(TransactionsCompanion(categoryId: Value(targetId)));
        await (db.update(db.templates)..where((t) => t.categoryId.equals(id)))
            .write(TemplatesCompanion(categoryId: Value(targetId)));
        await (db.update(db.sellers)..where((t) => t.categoryId.equals(id)))
            .write(SellersCompanion(categoryId: Value(targetId)));
        if (debugFailAfterMove != null) await debugFailAfterMove();
        await (db.delete(db.categories)..where((x) => x.id.equals(id))).go();
        return moved;
      });

  Future<void> reorderCategories(List<int> orderedIds) => db.transaction(() async {
        for (var i = 0; i < orderedIds.length; i++) {
          await (db.update(db.categories)..where((c) => c.id.equals(orderedIds[i])))
              .write(CategoriesCompanion(sortOrder: Value(i)));
        }
      });

  Stream<List<String>> watchUsedCurrencies() => db
      .customSelect('SELECT DISTINCT currency_code AS c FROM transactions ORDER BY c',
          readsFrom: {db.transactions})
      .watch()
      .map((r) => r.map((e) => e.read<String>('c')).toList());

  // ---------- ringkasan untuk widget ----------

  Future<List<CurrencyTotal>> totals(TxFilter f, {DateTime? now}) async =>
      summarize((await rows(f, now: now)).map((r) => r.tx));
}
