import 'package:flutter/foundation.dart';

import '../../../core/db/database.dart';
import '../../../core/util/dates.dart';

enum QuickPeriod {
  today('Hari ini'),
  week('Minggu ini'),
  month('Bulan ini'),
  all('Semua');

  final String label;
  const QuickPeriod(this.label);
}

/// Rentang hari lokal; [end] inklusif (hari terakhir).
@immutable
class DayRange {
  final DateTime start;
  final DateTime end;
  const DayRange(this.start, this.end);

  @override
  bool operator ==(Object other) => other is DayRange && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
}

/// Filter gabungan (semua kondisi di-AND).
@immutable
class TxFilter {
  /// Jika [customRange] terisi, ia menang atas [period].
  final QuickPeriod period;
  final DayRange? customRange;
  final Set<int> categoryIds;
  final TxType? type;
  final Set<String> currencies;
  final String query;

  const TxFilter({
    this.period = QuickPeriod.month,
    this.customRange,
    this.categoryIds = const {},
    this.type,
    this.currencies = const {},
    this.query = '',
  });

  static const all = TxFilter(period: QuickPeriod.all);

  /// Rentang [mulai, akhir) dalam waktu lokal, dihitung saat dipakai agar tetap
  /// benar bila lewat tengah malam. null = tanpa batas tanggal.
  ({DateTime start, DateTime endExclusive})? resolveRange(DateTime now) {
    final r = customRange;
    if (r != null) {
      return (start: startOfDay(r.start), endExclusive: addDays(startOfDay(r.end), 1));
    }
    final today = startOfDay(now);
    switch (period) {
      case QuickPeriod.today:
        return (start: today, endExclusive: addDays(today, 1));
      case QuickPeriod.week:
        final s = startOfWeek(now);
        return (start: s, endExclusive: addDays(s, 7));
      case QuickPeriod.month:
        final s = startOfMonth(now);
        return (start: s, endExclusive: DateTime(s.year, s.month + 1));
      case QuickPeriod.all:
        return null;
    }
  }

  /// Jumlah filter lanjutan aktif (di luar periode cepat).
  int get advancedCount =>
      (customRange != null ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (type != null ? 1 : 0) +
      (currencies.isNotEmpty ? 1 : 0) +
      (query.trim().isNotEmpty ? 1 : 0);

  TxFilter copyWith({
    QuickPeriod? period,
    Object? customRange = _keep,
    Set<int>? categoryIds,
    Object? type = _keep,
    Set<String>? currencies,
    String? query,
  }) =>
      TxFilter(
        period: period ?? this.period,
        customRange: identical(customRange, _keep) ? this.customRange : customRange as DayRange?,
        categoryIds: categoryIds ?? this.categoryIds,
        type: identical(type, _keep) ? this.type : type as TxType?,
        currencies: currencies ?? this.currencies,
        query: query ?? this.query,
      );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is TxFilter &&
      other.period == period &&
      other.customRange == customRange &&
      setEquals(other.categoryIds, categoryIds) &&
      other.type == type &&
      setEquals(other.currencies, currencies) &&
      other.query == query;

  @override
  int get hashCode => Object.hash(period, customRange, Object.hashAllUnordered(categoryIds),
      type, Object.hashAllUnordered(currencies), query);
}
