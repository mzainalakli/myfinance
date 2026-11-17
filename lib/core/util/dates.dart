/// Util tanggal. Waktu disimpan UTC epoch ms; pengelompokan memakai waktu lokal.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Awal minggu (Senin).
DateTime startOfWeek(DateTime d) => addDays(startOfDay(d), -(d.weekday - 1));
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

int toEpochMs(DateTime d) => d.toUtc().millisecondsSinceEpoch;
DateTime fromEpochMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
