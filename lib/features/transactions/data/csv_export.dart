import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_config.dart';
import '../../../core/csv/transaction_csv.dart';
import 'summary.dart';

/// Baris DB -> bentuk netral CSV (format didefinisikan di core/csv/transaction_csv.dart).
TxCsvRecord toCsvRecord(TxRow r) => TxCsvRecord(
      occurredAt: DateTime.fromMillisecondsSinceEpoch(r.tx.occurredAt, isUtc: true),
      type: r.tx.type,
      category: r.category.name,
      amountMinor: r.tx.amountMinor,
      currency: r.money.currency,
      note: r.tx.note,
      icon: r.category.icon,
      color: r.category.color,
      invoiceNo: r.tx.invoiceNo,
    );

String buildCsv(List<TxRow> rows) => encodeTransactions(rows.map(toCsvRecord));

/// Berkas CSV dengan BOM UTF-8 agar Excel membaca benar (pembaca impor membuang BOM).
String withBom(String csv) => '﻿$csv';

String _stamp(DateTime n) =>
    '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';

Future<void> shareCsvText(String csv, String fileName) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsString(withBom(csv));
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: fileName));
}

Future<void> shareCsv(List<TxRow> rows) =>
    shareCsvText(buildCsv(rows), '${AppConfig.filePrefix}-${_stamp(DateTime.now())}.csv');

Future<void> shareCsvTemplate() =>
    shareCsvText(encodeTemplate(), '${AppConfig.filePrefix}-template.csv');
