import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/money/money.dart';
import '../../../core/util/dates.dart';
import 'summary.dart';
import 'tx_filter.dart';

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

  Future<int> addTransaction({
    required TxType type,
    required Money money,
    required int categoryId,
    String note = '',
    DateTime? occurredAt,
    DateTime? now,
  }) {
    final n = toEpochMs(now ?? DateTime.now());
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          type: type,
          amountMinor: money.minor,
          currencyCode: money.currency.code,
          categoryId: categoryId,
          note: Value(note.trim()),
          occurredAt: occurredAt == null ? n : toEpochMs(occurredAt),
          createdAt: n,
          updatedAt: n,
        ));
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

  Future<int> addCategory({
    required String name,
    required String icon,
    required int color,
    required TxType type,
  }) async {
    final maxOrder = await (db.selectOnly(db.categories)
          ..addColumns([db.categories.sortOrder.max()])
          ..where(db.categories.type.equalsValue(type)))
        .map((r) => r.read(db.categories.sortOrder.max()))
        .getSingle();
    return db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name.trim(), icon: icon, color: color, type: type,
          sortOrder: Value((maxOrder ?? -1) + 1),
        ));
  }

  Future<void> updateCategory(int id, {String? name, String? icon, int? color}) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        icon: icon == null ? const Value.absent() : Value(icon),
        color: color == null ? const Value.absent() : Value(color),
      ));

  /// "Hapus" = arsip (soft delete): transaksi lama tetap utuh.
  Future<void> setArchived(int id, bool archived) =>
      (db.update(db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(isArchived: Value(archived)));

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
