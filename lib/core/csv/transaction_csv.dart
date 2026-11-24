import 'dart:convert';
import 'dart:typed_data';

import '../db/database.dart';
import '../money/currencies.dart';
import '../money/currency.dart';
import '../money/money.dart';
import '../util/category_style.dart';
import 'csv_reader.dart';

/// KONTRAK FORMAT CSV transaksi: satu-satunya tempat penulis (ekspor) dan pembaca (impor).
/// Dokumentasi: docs/FORMAT_CSV.md. Ubah di sini saja agar keduanya tak pernah berbeda.
class TxCsv {
  static const colDate = 'Tanggal';
  static const colType = 'Jenis';
  static const colCategory = 'Kategori';
  static const colAmount = 'Nominal';
  static const colCurrency = 'Mata uang';
  static const colNote = 'Catatan';
  static const colIcon = 'Ikon';
  static const colColor = 'Warna';
  static const colInvoice = 'no_faktur';

  /// Urutan penulisan. Kolom wajib dibaca; Ikon/Warna/no_faktur opsional (berkas lama tanpa kolom ini tetap terbaca).
  static const header = [colDate, colType, colCategory, colAmount, colCurrency, colNote, colIcon, colColor, colInvoice];
  static const typeIncome = 'Masuk';
  static const typeExpense = 'Keluar';

  /// Batas ukuran berkas yang diterima pembaca.
  static const maxBytes = 25 * 1024 * 1024;
  static const maxCategoryName = 40;
}

/// Satu transaksi dalam bentuk netral (tanpa id/timestamp internal).
class TxCsvRecord {
  final int line; // baris di berkas (0 bila dibuat dari DB)
  final DateTime occurredAt;

  /// true bila waktu di berkas tak punya detik (format ekspor lama) -> pencocokan duplikat per menit.
  final bool minutePrecision;
  final TxType type;
  final String category;
  final int amountMinor;
  final Currency currency;
  final String note;
  final String? icon;
  final int? color;

  /// Nomor faktur elektronik (opsional, huruf besar tanpa strip).
  final String? invoiceNo;

  const TxCsvRecord({
    this.line = 0,
    required this.occurredAt,
    this.minutePrecision = false,
    required this.type,
    required this.category,
    required this.amountMinor,
    required this.currency,
    this.note = '',
    this.icon,
    this.color,
    this.invoiceNo,
  });
}

class TxCsvRowError {
  final int line;
  final String column;
  final String message;
  const TxCsvRowError(this.line, this.column, this.message);
  @override
  String toString() => 'Baris $line, kolom "$column": $message';
}

class TxCsvParseResult {
  final List<TxCsvRecord> records;
  final List<TxCsvRowError> errors;

  /// Galat yang membatalkan seluruh berkas (kosong, header salah, bukan CSV).
  final String? fatal;
  final String delimiter;
  final int totalRows;
  const TxCsvParseResult({
    this.records = const [],
    this.errors = const [],
    this.fatal,
    this.delimiter = ',',
    this.totalRows = 0,
  });
}

// ---------------------------------------------------------------- penulis

final _protectRe = RegExp(r"^'*[=+\-@\t\r]");

/// Pelindung formula-injection: sel yang (setelah nol atau lebih `'`) diawali `= + - @ TAB CR`
/// diberi awalan `'`. Pembaca membuangnya tepat satu kali -> bolak-balik persis.
String _protect(String v) => _protectRe.hasMatch(v) ? "'$v" : v;

String _unprotect(String v) => _protectRe.hasMatch(v) && v.startsWith("'") ? v.substring(1) : v;

String _quote(String v) =>
    v.contains(RegExp('[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

String _two(int n) => n.toString().padLeft(2, '0');

/// ISO 8601 lokal dengan milidetik dan offset: 2026-11-18T08:05:07.123+07:00 (titik waktu persis).
String formatCsvDate(DateTime t) {
  final d = t.toLocal();
  final off = d.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final a = off.abs();
  return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.${d.millisecond.toString().padLeft(3, '0')}'
      '$sign${_two(a.inHours)}:${_two(a.inMinutes % 60)}';
}

String _colorHex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Tulis CSV (tanpa BOM; BOM ditambahkan saat menyimpan berkas).
String encodeTransactions(Iterable<TxCsvRecord> records) {
  final b = StringBuffer('${TxCsv.header.join(',')}\r\n');
  for (final r in records) {
    b.write([
      formatCsvDate(r.occurredAt),
      r.type == TxType.income ? TxCsv.typeIncome : TxCsv.typeExpense,
      _quote(_protect(r.category)),
      Money(r.amountMinor, r.currency).toPlainString(),
      r.currency.code,
      _quote(_protect(r.note)),
      r.icon ?? '',
      r.color == null ? '' : _colorHex(r.color!),
      r.invoiceNo ?? '',
    ].join(','));
    b.write('\r\n');
  }
  return b.toString();
}

/// Template kosong: header + 2 baris contoh (memakai penulis yang sama).
String encodeTemplate({DateTime? now}) {
  final t = now ?? DateTime.now();
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');
  return encodeTransactions([
    TxCsvRecord(
        occurredAt: DateTime(t.year, t.month, t.day, 8, 30),
        type: TxType.expense,
        category: 'Makan & Minum',
        amountMinor: 18000,
        currency: idr,
        note: 'Kopi'),
    TxCsvRecord(
        occurredAt: DateTime(t.year, t.month, t.day, 9),
        type: TxType.income,
        category: 'Gaji',
        amountMinor: 150000,
        currency: usd,
        note: 'Contoh: 1.500,00 USD ditulis 1500.00'),
  ]);
}

// ---------------------------------------------------------------- pembaca

enum _Col { date, type, category, amount, currency, note, icon, color, invoice }

const _aliases = <String, _Col>{
  'tanggal': _Col.date, 'date': _Col.date, 'waktu': _Col.date,
  'jenis': _Col.type, 'type': _Col.type, 'tipe': _Col.type,
  'kategori': _Col.category, 'category': _Col.category,
  'nominal': _Col.amount, 'amount': _Col.amount, 'jumlah': _Col.amount,
  'matauang': _Col.currency, 'currency': _Col.currency, 'mata_uang': _Col.currency,
  'catatan': _Col.note, 'note': _Col.note, 'notes': _Col.note, 'keterangan': _Col.note,
  'ikon': _Col.icon, 'icon': _Col.icon,
  'warna': _Col.color, 'color': _Col.color, 'colour': _Col.color,
  'nofaktur': _Col.invoice, 'invoice': _Col.invoice, 'invoiceno': _Col.invoice, 'nomorfaktur': _Col.invoice,
};

String _norm(String h) => h.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

const _colLabels = {
  _Col.date: TxCsv.colDate,
  _Col.type: TxCsv.colType,
  _Col.category: TxCsv.colCategory,
  _Col.amount: TxCsv.colAmount,
  _Col.currency: TxCsv.colCurrency,
};

/// Parse teks CSV. Tidak pernah melempar: masalah dilaporkan lewat [TxCsvParseResult].
TxCsvParseResult parseTransactionCsv(String text) {
  if (text.contains('\u0000')) {
    return const TxCsvParseResult(fatal: 'Berkas ini bukan CSV teks (berisi data biner).');
  }
  final table = readCsv(text);
  if (table.error != null) return TxCsvParseResult(fatal: table.error, delimiter: table.delimiter);
  if (table.records.isEmpty) {
    return TxCsvParseResult(fatal: 'Berkas kosong.', delimiter: table.delimiter);
  }
  final head = table.records.first;
  final idx = <_Col, int>{};
  for (var i = 0; i < head.fields.length; i++) {
    final c = _aliases[_norm(head.fields[i])];
    if (c != null) idx.putIfAbsent(c, () => i);
  }
  final missing = [for (final e in _colLabels.entries) if (!idx.containsKey(e.key)) e.value];
  if (missing.isNotEmpty) {
    return TxCsvParseResult(
      fatal: 'Header tidak dikenali. Kolom wajib yang tidak ditemukan: ${missing.join(', ')}. '
          'Header yang diharapkan: ${TxCsv.header.take(6).join(', ')}.',
      delimiter: table.delimiter,
    );
  }
  final rows = table.records.skip(1).toList();
  if (rows.isEmpty) {
    return TxCsvParseResult(fatal: 'Berkas hanya berisi header, tidak ada transaksi.', delimiter: table.delimiter);
  }

  final records = <TxCsvRecord>[];
  final errors = <TxCsvRowError>[];
  for (final r in rows) {
    String cell(_Col c) {
      final i = idx[c];
      return i == null || i >= r.fields.length ? '' : r.fields[i];
    }

    final before = errors.length;
    void err(String col, String msg) => errors.add(TxCsvRowError(r.line, col, msg));

    // tanggal
    final rawDate = cell(_Col.date);
    DateTime? when;
    var minutePrecision = false;
    if (rawDate.isEmpty) {
      err(TxCsv.colDate, 'tanggal kosong.');
    } else {
      when = DateTime.tryParse(rawDate);
      if (when == null) {
        err(TxCsv.colDate,
            'tanggal "$rawDate" tidak terbaca. Gunakan format 2026-11-18T08:05:00+07:00 atau 2026-11-18 08:05.');
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
        when = DateTime(when.year, when.month, when.day, 12); // hanya tanggal: tengah hari lokal
      } else {
        minutePrecision = !RegExp(r'\d{2}:\d{2}:\d{2}').hasMatch(rawDate);
      }
    }

    // jenis
    TxType? type;
    final rawType = cell(_Col.type).toLowerCase();
    if (const {'masuk', 'income', 'pemasukan', 'in'}.contains(rawType)) {
      type = TxType.income;
    } else if (const {'keluar', 'expense', 'pengeluaran', 'out'}.contains(rawType)) {
      type = TxType.expense;
    } else {
      err(TxCsv.colType, 'jenis "${cell(_Col.type)}" tidak dikenal. Gunakan "Masuk" atau "Keluar".');
    }

    // kategori
    final category = _unprotect(cell(_Col.category)).trim();
    if (category.isEmpty) {
      err(TxCsv.colCategory, 'kategori kosong.');
    } else if (category.length > TxCsv.maxCategoryName) {
      err(TxCsv.colCategory, 'nama kategori terlalu panjang (maks ${TxCsv.maxCategoryName} karakter).');
    }

    // mata uang
    final code = cell(_Col.currency).toUpperCase();
    final currency = code.isEmpty ? null : findCurrency(code);
    if (code.isEmpty) {
      err(TxCsv.colCurrency, 'mata uang kosong.');
    } else if (currency == null) {
      err(TxCsv.colCurrency, 'mata uang "$code" tidak dikenal (harus kode ISO 4217, mis. IDR, USD).');
    }

    // nominal
    int? minor;
    if (currency != null) {
      final res = _parseAmount(cell(_Col.amount), currency, table.delimiter);
      if (res.$2 != null) {
        err(TxCsv.colAmount, res.$2!);
      } else {
        minor = res.$1;
      }
    } else if (cell(_Col.amount).isEmpty) {
      err(TxCsv.colAmount, 'nominal kosong.');
    }

    if (errors.length > before) continue;

    // opsional
    final icon = cell(_Col.icon);
    final colorRaw = cell(_Col.color).replaceFirst('#', '');
    final color = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(colorRaw) ? 0xFF000000 | int.parse(colorRaw, radix: 16) : null;
    final invoice = _unprotect(cell(_Col.invoice)).trim().toUpperCase();
    records.add(TxCsvRecord(
      line: r.line,
      occurredAt: when!,
      minutePrecision: minutePrecision,
      type: type!,
      category: category,
      amountMinor: minor!,
      currency: currency!,
      note: _unprotect(cell(_Col.note)).trim(),
      icon: categoryIcons.containsKey(icon) ? icon : null,
      color: color,
      invoiceNo: invoice.isEmpty ? null : invoice,
    ));
  }
  return TxCsvParseResult(records: records, errors: errors, delimiter: table.delimiter, totalRows: rows.length);
}

/// (minor, pesan galat). Titik = desimal; "12,50" diterima bila pemisah berkas `;`.
(int?, String?) _parseAmount(String raw, Currency c, String delimiter) {
  var s = raw.trim();
  if (s.isEmpty) return (null, 'nominal kosong.');
  if (delimiter == ';' && RegExp(r'^\d+,\d+$').hasMatch(s)) s = s.replaceFirst(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
    if (s.startsWith('-')) return (null, 'nominal "$raw" harus lebih dari 0 (jenis dibedakan oleh kolom Jenis).');
    return (
      null,
      'nominal "$raw" tidak valid. Tulis angka dengan titik sebagai desimal dan tanpa pemisah ribuan (mis. 18000 atau 12.50).'
    );
  }
  final parts = s.split('.');
  var whole = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
  var frac = parts.length == 2 ? parts[1] : '';
  if (frac.length > c.decimals) {
    final extra = frac.substring(c.decimals);
    if (extra.replaceAll('0', '').isNotEmpty) {
      return (null, 'nominal "$raw" punya ${frac.length} desimal, melebihi batas ${c.code} (${c.decimals} desimal). Tidak dibulatkan.');
    }
    frac = frac.substring(0, c.decimals);
  }
  final money = Money.parse('${whole.isEmpty ? '0' : whole}${frac.isEmpty ? '' : ',$frac'}', c);
  if (money == null) return (null, 'nominal "$raw" terlalu besar atau tidak valid.');
  if (money.minor <= 0) return (null, 'nominal "$raw" harus lebih dari 0.');
  return (money.minor, null);
}

/// Dipakai `compute()` agar parsing berkas besar tidak membekukan UI.
TxCsvParseResult parseTransactionCsvBytes(Uint8List bytes) {
  if (bytes.length > TxCsv.maxBytes) {
    return TxCsvParseResult(fatal: 'Berkas terlalu besar (maks ${TxCsv.maxBytes ~/ (1024 * 1024)} MB).');
  }
  return parseTransactionCsv(utf8.decode(bytes, allowMalformed: true));
}
