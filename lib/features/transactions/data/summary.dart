import '../../../core/db/database.dart';
import '../../../core/money/currencies.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

/// Transaksi + kategorinya (untuk daftar).
class TxRow {
  final Transaction tx;
  final Category category;
  const TxRow(this.tx, this.category);

  Money get money => Money(tx.amountMinor, currencyByCode(tx.currencyCode));
  bool get isIncome => tx.type == TxType.income;
}

/// Total satu mata uang. Mata uang berbeda TIDAK pernah dijumlahkan.
class CurrencyTotal {
  final Currency currency;
  final int incomeMinor;
  final int expenseMinor;
  final int count;
  const CurrencyTotal(this.currency, this.incomeMinor, this.expenseMinor, this.count);

  Money get income => Money(incomeMinor, currency);
  Money get expense => Money(expenseMinor, currency);
  Money get net => Money(incomeMinor - expenseMinor, currency);
}

/// Rekap per mata uang; urut dari jumlah transaksi terbanyak, lalu kode.
List<CurrencyTotal> summarize(Iterable<Transaction> txs) {
  final inc = <String, int>{};
  final exp = <String, int>{};
  final cnt = <String, int>{};
  for (final t in txs) {
    cnt[t.currencyCode] = (cnt[t.currencyCode] ?? 0) + 1;
    final target = t.type == TxType.income ? inc : exp;
    target[t.currencyCode] = (target[t.currencyCode] ?? 0) + t.amountMinor;
  }
  final codes = cnt.keys.toList()
    ..sort((a, b) {
      final c = cnt[b]!.compareTo(cnt[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final c in codes) CurrencyTotal(currencyByCode(c), inc[c] ?? 0, exp[c] ?? 0, cnt[c]!),
  ];
}
