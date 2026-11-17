import '../../core/db/database.dart';
import '../../core/util/dates.dart';
import '../transactions/data/summary.dart';

class CategorySlice {
  final Category category;
  final int minor;
  const CategorySlice(this.category, this.minor);
}

class MonthBar {
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
  const MonthBar(this.month, this.incomeMinor, this.expenseMinor);
}

class TrendPoint {
  final DateTime day;
  final int cumulativeMinor;
  const TrendPoint(this.day, this.cumulativeMinor);
}

/// Mata uang yang ada di data, diurut dari transaksi terbanyak.
List<String> currenciesIn(List<TxRow> rows) =>
    summarize(rows.map((r) => r.tx)).map((t) => t.currency.code).toList();

List<CategorySlice> categoryBreakdown(List<TxRow> rows, TxType type, String currency) {
  final sums = <int, int>{};
  final cats = <int, Category>{};
  for (final r in rows) {
    if (r.tx.type != type || r.tx.currencyCode != currency) continue;
    sums[r.category.id] = (sums[r.category.id] ?? 0) + r.tx.amountMinor;
    cats[r.category.id] = r.category;
  }
  final out = [for (final e in sums.entries) CategorySlice(cats[e.key]!, e.value)]
    ..sort((a, b) => b.minor.compareTo(a.minor));
  return out;
}

/// Total per bulan (urut naik), hanya bulan yang punya data; paling banyak [maxMonths] terakhir.
List<MonthBar> monthlyBars(List<TxRow> rows, String currency, {int maxMonths = 12}) {
  final inc = <DateTime, int>{};
  final exp = <DateTime, int>{};
  for (final r in rows) {
    if (r.tx.currencyCode != currency) continue;
    final m = startOfMonth(fromEpochMs(r.tx.occurredAt));
    final t = r.isIncome ? inc : exp;
    t[m] = (t[m] ?? 0) + r.tx.amountMinor;
  }
  final months = {...inc.keys, ...exp.keys}.toList()..sort();
  final last = months.length > maxMonths ? months.sublist(months.length - maxMonths) : months;
  return [for (final m in last) MonthBar(m, inc[m] ?? 0, exp[m] ?? 0)];
}

/// Selisih kumulatif per hari (mulai 0 pada awal data terfilter), diringkas ke <= [maxPoints].
List<TrendPoint> balanceTrend(List<TxRow> rows, String currency, {int maxPoints = 60}) {
  final perDay = <DateTime, int>{};
  for (final r in rows) {
    if (r.tx.currencyCode != currency) continue;
    final d = startOfDay(fromEpochMs(r.tx.occurredAt));
    perDay[d] = (perDay[d] ?? 0) + (r.isIncome ? r.tx.amountMinor : -r.tx.amountMinor);
  }
  final days = perDay.keys.toList()..sort();
  var run = 0;
  final pts = <TrendPoint>[];
  for (final d in days) {
    run += perDay[d]!;
    pts.add(TrendPoint(d, run));
  }
  if (pts.length <= maxPoints) return pts;
  // ambil titik terakhir tiap ember agar bentuk kurva terjaga
  final step = pts.length / maxPoints;
  final out = <TrendPoint>[];
  for (var i = 1; i <= maxPoints; i++) {
    out.add(pts[(i * step).ceil() - 1]);
  }
  return out;
}
