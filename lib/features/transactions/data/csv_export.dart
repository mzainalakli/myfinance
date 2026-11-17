import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_config.dart';
import '../../../core/util/format.dart';
import '../../../core/util/dates.dart';
import 'summary.dart';

String _esc(String v) {
  // Cegah injeksi rumus saat dibuka di spreadsheet.
  var s = v;
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp('[",\n\r]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// CSV: tanggal (ISO lokal), jenis, kategori, nominal (titik desimal), mata uang, catatan.
String buildCsv(List<TxRow> rows) {
  final b = StringBuffer('Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan\r\n');
  for (final r in rows) {
    final d = fromEpochMs(r.tx.occurredAt);
    final date =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${timeLabel(d).replaceAll('.', ':')}';
    b.write([
      date,
      r.isIncome ? 'Masuk' : 'Keluar',
      _esc(r.category.name),
      r.money.toPlainString(),
      r.tx.currencyCode,
      _esc(r.tx.note),
    ].join(','));
    b.write('\r\n');
  }
  return b.toString();
}

Future<void> shareCsv(List<TxRow> rows) async {
  final dir = await getTemporaryDirectory();
  final n = DateTime.now();
  final name =
      '${AppConfig.filePrefix}-${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}.csv';
  final f = File('${dir.path}/$name');
  // BOM agar Excel membaca UTF-8 dengan benar.
  await f.writeAsString('﻿${buildCsv(rows)}');
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: name));
}
