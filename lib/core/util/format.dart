import 'package:intl/intl.dart';

import '../strings.dart';
import 'dates.dart';

final _dayFmt = DateFormat('EEE, d MMM yyyy', 'id_ID');
final _monthFmt = DateFormat('MMMM yyyy', 'id_ID');
final _shortMonthFmt = DateFormat('MMM yy', 'id_ID');
final _shortDayFmt = DateFormat('d MMM', 'id_ID');
final _timeFmt = DateFormat('HH.mm', 'id_ID');

String dayLabel(DateTime d, {DateTime? now}) {
  final today = startOfDay(now ?? DateTime.now());
  final day = startOfDay(d);
  if (day == today) return S.today;
  if (day == addDays(today, -1)) return S.yesterday;
  return _dayFmt.format(d);
}

String monthLabel(DateTime d) => _monthFmt.format(d);
String shortMonthLabel(DateTime d) => _shortMonthFmt.format(d);
String shortDayLabel(DateTime d) => _shortDayFmt.format(d);
String timeLabel(DateTime d) => _timeFmt.format(d);
String fullDayLabel(DateTime d) => _dayFmt.format(d);

/// Angka ringkas untuk sumbu grafik: 1,5rb · 2jt · 3M.
String compactNumber(double v) {
  final a = v.abs();
  String f(double x, String u) {
    final s = x >= 100 || x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1).replaceAll('.', ',');
    return '$s$u';
  }

  final sign = v < 0 ? '-' : '';
  if (a >= 1e12) return '$sign${f(a / 1e12, 'T')}';
  if (a >= 1e9) return '$sign${f(a / 1e9, 'M')}';
  if (a >= 1e6) return '$sign${f(a / 1e6, 'jt')}';
  if (a >= 1e3) return '$sign${f(a / 1e3, 'rb')}';
  return '$sign${f(a, '')}';
}
