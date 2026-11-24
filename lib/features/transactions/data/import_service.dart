import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/csv/transaction_csv.dart';
import '../../../core/db/database.dart';
import '../../../core/money/currency.dart';
import '../../../core/util/category_style.dart';
import '../../../core/util/dates.dart';
import 'csv_export.dart';
import 'repository.dart';
import 'summary.dart';
import 'tx_filter.dart';

enum ImportMode { merge, replace }

class NewCategory {
  final String name;
  final TxType type;
  final String icon;
  final int color;
  const NewCategory(this.name, this.type, this.icon, this.color);
}

/// Hasil analisis sebelum menulis apa pun (untuk layar pratinjau).
class ImportPlan {
  final ImportMode mode;
  final List<TxCsvRecord> toInsert;
  final int duplicates;
  final List<TxCsvRowError> errors;
  final List<NewCategory> newCategories;
  final DateTime? from;
  final DateTime? to;
  final List<CurrencyTotal> totals; // dari yang akan dimasukkan, per mata uang
  const ImportPlan({
    required this.mode,
    required this.toInsert,
    required this.duplicates,
    required this.errors,
    required this.newCategories,
    required this.from,
    required this.to,
    required this.totals,
  });
}

class ImportResult {
  final int added;
  final int skipped;
  final int failed;
  final String? backupPath;
  const ImportResult({
    required this.added,
    required this.skipped,
    required this.failed,
    this.backupPath,
  });
}

String _catKey(TxType t, String name) => categoryKey(t, name);

/// Sidik jari transaksi: waktu + jenis + nominal + mata uang + kategori + catatan + nomor faktur.
String _fp(
  int timeKey,
  TxType t,
  int minor,
  String cur,
  String cat,
  String note,
  String? invoice,
) =>
    '$timeKey|${t.name}|$minor|$cur|${cat.trim().toLowerCase()}|${note.trim()}|${invoice ?? ''}';

class ImportService {
  final AppDatabase db;
  final Directory? backupDir;
  ImportService(this.db, {this.backupDir});

  Repository get _repo => Repository(db);

  /// Analisis tanpa menulis. Deduplikasi berbasis jumlah (multiset): n kembar di berkas dan m di DB
  /// -> hanya max(0, n - m) yang ditambahkan. Pada mode [ImportMode.replace] DB dianggap kosong.
  Future<ImportPlan> plan(TxCsvParseResult parsed, ImportMode mode) async {
    final existingCats = await db.select(db.categories).get();
    final catKeys = {for (final c in existingCats) _catKey(c.type, c.name)};

    var toInsert = parsed.records;
    var dup = 0;
    if (mode == ImportMode.merge && parsed.records.isNotEmpty) {
      final rows = await _repo.rows(TxFilter.all);
      // dua indeks atas baris DB yang sama: persis (ms) dan per menit (berkas ekspor lama tanpa detik)
      final exact = <String, List<int>>{};
      final minute = <String, List<int>>{};
      for (final r in rows) {
        final t = r.tx;
        (exact[_fp(
                  t.occurredAt,
                  t.type,
                  t.amountMinor,
                  t.currencyCode,
                  r.category.name,
                  t.note,
                  t.invoiceNo,
                )] ??=
                [])
            .add(t.id);
        (minute[_fp(
                  t.occurredAt ~/ 60000,
                  t.type,
                  t.amountMinor,
                  t.currencyCode,
                  r.category.name,
                  t.note,
                  t.invoiceNo,
                )] ??=
                [])
            .add(t.id);
      }
      final used = <int>{};
      toInsert = [];
      // Indeks unik nomor faktur: faktur yang sudah ada di DB (atau muncul lebih dulu di berkas) dihitung duplikat,
      // apa pun kolom lainnya, agar penulisan tidak melanggar unique index dan membatalkan seluruh impor.
      final invoices = {
        for (final r in rows)
          if (r.tx.invoiceNo != null) r.tx.invoiceNo!,
      };
      for (final rec in parsed.records) {
        if (rec.invoiceNo != null && !invoices.add(rec.invoiceNo!)) {
          dup++;
          continue;
        }
        final ms = toEpochMs(rec.occurredAt);
        final idx = rec.minutePrecision ? minute : exact;
        final key = _fp(
          rec.minutePrecision ? ms ~/ 60000 : ms,
          rec.type,
          rec.amountMinor,
          rec.currency.code,
          rec.category,
          rec.note,
          rec.invoiceNo,
        );
        final list = idx[key];
        final hit = list?.cast<int?>().firstWhere(
          (id) => !used.contains(id),
          orElse: () => null,
        );
        if (hit != null) {
          used.add(hit);
          dup++;
        } else {
          toInsert.add(rec);
        }
      }
    } else if (parsed.records.isNotEmpty) {
      // Ganti semua (DB dianggap kosong): hanya nomor faktur kembar di dalam berkas yang perlu disaring.
      final seen = <String>{};
      toInsert = [];
      for (final rec in parsed.records) {
        if (rec.invoiceNo != null && !seen.add(rec.invoiceNo!)) {
          dup++;
        } else {
          toInsert.add(rec);
        }
      }
    }

    // kategori baru (dari yang benar-benar akan dimasukkan), tanpa duplikat
    final seen = <String>{};
    final fresh = <NewCategory>[];
    for (final r in toInsert) {
      final k = _catKey(r.type, r.category);
      if (catKeys.contains(k) || !seen.add(k)) continue;
      fresh.add(_newCategory(r));
    }

    DateTime? from, to;
    for (final r in parsed.records) {
      if (from == null || r.occurredAt.isBefore(from)) from = r.occurredAt;
      if (to == null || r.occurredAt.isAfter(to)) to = r.occurredAt;
    }
    return ImportPlan(
      mode: mode,
      toInsert: toInsert,
      duplicates: dup,
      errors: parsed.errors,
      newCategories: fresh,
      from: from?.toLocal(),
      to: to?.toLocal(),
      totals: _totals(toInsert),
    );
  }

  NewCategory _newCategory(TxCsvRecord r) => NewCategory(
    r.category,
    r.type,
    r.icon ?? 'more',
    r.color ??
        categoryColors[r.category.hashCode.abs() % categoryColors.length],
  );

  List<CurrencyTotal> _totals(List<TxCsvRecord> recs) {
    final inc = <Currency, int>{},
        exp = <Currency, int>{},
        cnt = <Currency, int>{};
    for (final r in recs) {
      cnt[r.currency] = (cnt[r.currency] ?? 0) + 1;
      final m = r.type == TxType.income ? inc : exp;
      m[r.currency] = (m[r.currency] ?? 0) + r.amountMinor;
    }
    final cs = cnt.keys.toList()
      ..sort((a, b) {
        final c = cnt[b]!.compareTo(cnt[a]!);
        return c != 0 ? c : a.code.compareTo(b.code);
      });
    return [
      for (final c in cs) CurrencyTotal(c, inc[c] ?? 0, exp[c] ?? 0, cnt[c]!),
    ];
  }

  /// Cadangan ekspor data sekarang di penyimpanan privat aplikasi. Mengembalikan path berkas.
  Future<String> backupCurrent() async {
    final dir = backupDir;
    if (dir == null) throw StateError('Folder cadangan belum ditentukan.');
    await dir.create(recursive: true);
    final rows = await _repo.rows(TxFilter.all);
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'cadangan-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}.csv';
    final f = File('${dir.path}/$name');
    await f.writeAsString(withBom(buildCsv(rows)), flush: true);
    return f.path;
  }

  /// Tulis dalam SATU transaksi DB: galat di tengah jalan membatalkan semuanya (rollback).
  /// Mode ganti-semua: cadangan dibuat dan ditulis ke disk SEBELUM data dihapus.
  Future<ImportResult> execute(
    ImportPlan plan, {
    void Function(int done, int total)? onProgress,
    int chunk = 500,
  }) async {
    String? backup;
    if (plan.mode == ImportMode.replace) backup = await backupCurrent();

    await db.transaction(() async {
      if (plan.mode == ImportMode.replace) {
        await db.delete(db.transactions).go();
      }
      final cats = await db.select(db.categories).get();
      final ids = {for (final c in cats) _catKey(c.type, c.name): c.id};
      final nextOrder = <TxType, int>{
        for (final t in TxType.values)
          t:
              cats
                  .where((c) => c.type == t)
                  .fold<int>(-1, (m, c) => c.sortOrder > m ? c.sortOrder : m) +
              1,
      };
      for (final r in plan.toInsert) {
        final k = _catKey(r.type, r.category);
        if (ids.containsKey(k)) continue;
        final nc = _newCategory(r);
        final order = nextOrder[nc.type]!;
        nextOrder[nc.type] = order + 1;
        ids[k] = await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                name: nc.name,
                icon: nc.icon,
                color: nc.color,
                type: nc.type,
                sortOrder: Value(order),
              ),
            );
      }
      final now = toEpochMs(DateTime.now());
      final total = plan.toInsert.length;
      for (var i = 0; i < total; i += chunk) {
        final part = plan.toInsert.skip(i).take(chunk).toList();
        await db.batch((b) {
          for (final r in part) {
            b.insert(
              db.transactions,
              TransactionsCompanion.insert(
                type: r.type,
                amountMinor: r.amountMinor,
                currencyCode: r.currency.code,
                categoryId: ids[_catKey(r.type, r.category)]!,
                note: Value(r.note),
                occurredAt: toEpochMs(r.occurredAt),
                createdAt: now,
                updatedAt: now,
                invoiceNo: Value(r.invoiceNo),
              ),
            );
          }
        });
        onProgress?.call(
          i + part.length > total ? total : i + part.length,
          total,
        );
      }
    });

    return ImportResult(
      added: plan.toInsert.length,
      skipped: plan.duplicates,
      failed: plan.errors.length,
      backupPath: backup,
    );
  }
}
