import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';

part 'database.g.dart';

enum TxType { income, expense }

@TableIndex(name: 'idx_tx_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_tx_category', columns: {#categoryId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  /// Satuan terkecil (sen). Jangan pernah double.
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  /// UTC epoch milidetik.
  IntColumn get occurredAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [Transactions, Categories, Templates])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Naikkan angka ini dan tambah langkah di [onUpgrade] untuk setiap perubahan skema.
  static const int currentVersion = 1;

  @override
  int get schemaVersion => currentVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
        },
        onUpgrade: (m, from, to) async {
          // v1 -> v2 dst. ditambahkan di sini, berurutan:
          // if (from < 2) { await m.addColumn(...); }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedCategories() async {
    var i = 0;
    Future<void> add(String name, String icon, int color, TxType t) async {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name, icon: icon, color: color, type: t, sortOrder: Value(i++),
      ));
    }

    const x = TxType.expense;
    const m = TxType.income;
    await add('Makan & Minum', 'restaurant', 0xFFEF6C00, x);
    await add('Transportasi', 'bus', 0xFF1E88E5, x);
    await add('Belanja', 'bag', 0xFF8E24AA, x);
    await add('Tagihan', 'bill', 0xFF546E7A, x);
    await add('Kesehatan', 'health', 0xFFE53935, x);
    await add('Hiburan', 'movie', 0xFFD81B60, x);
    await add('Pendidikan', 'school', 0xFF3949AB, x);
    await add('Lainnya', 'more', 0xFF6D4C41, x);
    i = 0;
    await add('Gaji', 'salary', 0xFF43A047, m);
    await add('Bonus', 'bonus', 0xFFFBC02D, m);
    await add('Hadiah', 'gift', 0xFFD81B60, m);
    await add('Usaha', 'shop', 0xFF00897B, m);
    await add('Lainnya', 'more', 0xFF6D4C41, m);
  }

  /// Dipanggil saat aplikasi kembali aktif: tulisan dari popup (isolate/engine lain,
  /// koneksi lain ke file yang sama) tidak otomatis memicu stream di sini.
  void refreshAll() => notifyUpdates({
        const TableUpdate('transactions'),
        const TableUpdate('categories'),
        const TableUpdate('templates'),
      });
}

/// Satu file DB dipakai bersama aplikasi utama dan popup. WAL + busy_timeout agar
/// dua koneksi (dua engine Flutter dalam satu proses) tidak saling mengunci.
QueryExecutor openAppConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, AppConfig.dbFileName));
    return NativeDatabase(file, setup: (db) {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('PRAGMA synchronous = NORMAL');
    });
  });
}
