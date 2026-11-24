import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/core/util/dates.dart';
import 'package:myfinance/features/stats/stats_calculator.dart';
import 'package:myfinance/core/csv/transaction_csv.dart';
import 'package:myfinance/features/transactions/data/csv_export.dart';
import 'package:myfinance/features/transactions/data/summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

TxRow row(int id, TxType t, int minor, String cur, DateTime at, {String note = '', int cat = 1, String catName = 'Makan'}) {
  final tx = Transaction(
    id: id, type: t, amountMinor: minor, currencyCode: cur, categoryId: cat, note: note,
    occurredAt: toEpochMs(at), createdAt: 0, updatedAt: 0,
  );
  final c = Category(id: cat, name: catName, icon: 'more', color: 0xFF000000, type: t, sortOrder: 0, isArchived: false);
  return TxRow(tx, c);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  final rows = [
    row(1, TxType.expense, 1000, 'IDR', DateTime(2026, 9, 5), cat: 1, catName: 'Makan'),
    row(2, TxType.expense, 3000, 'IDR', DateTime(2026, 10, 5), cat: 2, catName: 'Transport'),
    row(3, TxType.expense, 500, 'IDR', DateTime(2026, 10, 6), cat: 1, catName: 'Makan'),
    row(4, TxType.income, 10000, 'IDR', DateTime(2026, 10, 7), cat: 3, catName: 'Gaji'),
    row(5, TxType.expense, 999, 'USD', DateTime(2026, 10, 7), cat: 1, catName: 'Makan'),
  ];

  test('currenciesIn: terbanyak dulu', () => expect(currenciesIn(rows), ['IDR', 'USD']));

  test('categoryBreakdown per mata uang, urut besar-kecil, tanpa campur USD', () {
    final s = categoryBreakdown(rows, TxType.expense, 'IDR');
    expect(s.map((e) => (e.category.name, e.minor)), [('Transport', 3000), ('Makan', 1500)]);
  });

  test('monthlyBars', () {
    final b = monthlyBars(rows, 'IDR');
    expect(b.length, 2);
    expect(b[0].month, DateTime(2026, 9));
    expect(b[0].expenseMinor, 1000);
    expect(b[1].incomeMinor, 10000);
    expect(b[1].expenseMinor, 3500);
  });

  test('balanceTrend kumulatif', () {
    final t = balanceTrend(rows, 'IDR');
    expect(t.map((e) => e.cumulativeMinor), [-1000, -4000, -4500, 5500]);
  });

  test('balanceTrend diringkas ke maxPoints dan mempertahankan titik akhir', () {
    final many = [for (var i = 0; i < 500; i++) row(i, TxType.income, 100, 'IDR', DateTime(2025, 1, 1).add(Duration(days: i)))];
    final t = balanceTrend(many, 'IDR', maxPoints: 50);
    expect(t.length, 50);
    expect(t.last.cumulativeMinor, 50000);
  });

  group('CSV', () {
    test('header, format nominal polos, kutip dan escape', () {
      final when = DateTime(2026, 11, 18, 8, 5, 7, 123);
      final csv = buildCsv([
        row(1, TxType.expense, 1250, 'USD', when, note: 'kopi, "enak"'),
        row(2, TxType.income, 5000000, 'IDR', DateTime(2026, 11, 1, 9), catName: 'Gaji'),
      ]);
      final lines = csv.trim().split('\r\n');
      expect(lines[0], 'Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan,Ikon,Warna,no_faktur');
      expect(lines[1], '${formatCsvDate(when)},Keluar,Makan,12.50,USD,"kopi, ""enak""",more,#000000,');
      expect(lines[1], startsWith('2026-11-18T08:05:07.123'));
      expect(lines[2], startsWith('2026-11-01T09:00:00.000'));
      expect(lines[2], endsWith(',Masuk,Gaji,5000000,IDR,,more,#000000,'));
    });

    test('mencegah injeksi rumus', () {
      final csv = buildCsv([row(1, TxType.expense, 100, 'IDR', DateTime(2026, 1, 1), note: '=1+1')]);
      expect(csv, contains(",'=1+1,"));
    });
  });

  test('Money dari TxRow memakai desimal mata uang', () {
    expect(row(1, TxType.expense, 1250, 'USD', DateTime(2026, 1, 1)).money, Money(1250, currencyByCode('USD')));
  });
}
