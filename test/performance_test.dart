import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/features/stats/stats_calculator.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/summary.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('10.000 transaksi: kueri, rekap, dan statistik tetap cepat', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    final cats = await repo.watchCategories(TxType.expense).first;
    final idr = currencyByCode('IDR');
    final usd = currencyByCode('USD');
    final base = DateTime(2024, 1, 1);

    final sw = Stopwatch()..start();
    await db.batch((b) {
      for (var i = 0; i < 10000; i++) {
        b.insert(
          db.transactions,
          TransactionsCompanion.insert(
            type: i % 7 == 0 ? TxType.income : TxType.expense,
            amountMinor: 1000 + i,
            currencyCode: i % 10 == 0 ? usd.code : idr.code,
            categoryId: cats[i % cats.length].id,
            note: Value('catatan $i'),
            occurredAt: base.add(Duration(hours: i * 2)).toUtc().millisecondsSinceEpoch,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
      }
    });
    final insertMs = sw.elapsedMilliseconds;

    sw
      ..reset()
      ..start();
    final rows = await repo.rows(TxFilter.all);
    final queryMs = sw.elapsedMilliseconds;
    expect(rows.length, 10000);

    sw
      ..reset()
      ..start();
    final totals = summarize(rows.map((r) => r.tx));
    final slices = categoryBreakdown(rows, TxType.expense, 'IDR');
    final bars = monthlyBars(rows, 'IDR');
    final trend = balanceTrend(rows, 'IDR');
    final calcMs = sw.elapsedMilliseconds;
    expect(totals.length, 2);
    expect(slices, isNotEmpty);
    expect(bars.length, 12);
    expect(trend.length, lessThanOrEqualTo(60));

    sw
      ..reset()
      ..start();
    final filtered = await repo.rows(TxFilter(query: 'catatan 99', period: QuickPeriod.all));
    final filterMs = sw.elapsedMilliseconds;
    expect(filtered, isNotEmpty);

    // ignore: avoid_print
    print('PERF insert=${insertMs}ms query=${queryMs}ms calc=${calcMs}ms filter=${filterMs}ms');
    expect(queryMs, lessThan(3000));
    expect(calcMs, lessThan(1000));
    await db.close();
  });
}
