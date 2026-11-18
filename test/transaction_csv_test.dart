import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/core/csv/csv_reader.dart';
import 'package:myfinance/core/csv/transaction_csv.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';

const _h = 'Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan';

TxCsvParseResult p(String s) => parseTransactionCsv(s);

void main() {
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');

  group('pembaca tingkat rendah', () {
    test('kolom berkutip, kutip ganda, koma dan baris baru di dalam kolom', () {
      final t = readCsv('a,"b,c","d ""q"" e","x\ny"\r\n1,2,3,4\n');
      expect(t.records.length, 2);
      expect(t.records[0].fields, ['a', 'b,c', 'd "q" e', 'x\ny']);
      expect(t.records[1].line, 3, reason: 'baris fisik, bukan indeks record');
    });
    test('BOM, CRLF, CR, baris kosong dilewati', () {
      final t = readCsv('﻿a,b\r\n\r\n1,2\r3,4');
      expect(t.records.map((r) => r.fields), [['a', 'b'], ['1', '2'], ['3', '4']]);
    });
    test('deteksi pemisah', () {
      expect(detectDelimiter('a;b;c\n1,2,3'), ';');
      expect(detectDelimiter('a,b,c'), ',');
      expect(detectDelimiter('a\tb\tc'), '\t');
      expect(detectDelimiter('"a;b",c'), ',');
    });
    test('kutip tidak tertutup dilaporkan', () => expect(readCsv('a,"b\n1,2').error, isNotNull));
    test('spasi berlebih dipangkas pada kolom tak berkutip, dipertahankan pada yang berkutip', () {
      expect(readCsv('  a , "  b  " ,c').records.single.fields, ['a', '  b  ', 'c']);
    });
  });

  group('variasi berkas valid', () {
    const row = '2026-11-18T08:05:07.123+07:00,Keluar,Makan & Minum,18000,IDR,Kopi';
    void ok(TxCsvParseResult r) {
      expect(r.fatal, isNull);
      expect(r.errors, isEmpty);
      expect(r.records.length, 1);
      final x = r.records.single;
      expect(x.amountMinor, 18000);
      expect(x.currency, idr);
      expect(x.type, TxType.expense);
      expect(x.category, 'Makan & Minum');
      expect(x.note, 'Kopi');
      expect(x.occurredAt.toUtc(), DateTime.utc(2026, 11, 18, 1, 5, 7, 123));
    }

    test('baku', () => ok(p('$_h\r\n$row\r\n')));
    test('BOM + LF', () => ok(p('﻿$_h\n$row\n')));
    test('titik koma', () => ok(p('${_h.replaceAll(',', ';')}\n${row.replaceAll(',', ';')}\n')));
    test('urutan kolom berbeda + kolom tambahan', () {
      ok(p('Catatan,Foo,Nominal,Mata uang,Tanggal,Kategori,Jenis\nKopi,x,18000,IDR,2026-11-18T08:05:07.123+07:00,Makan & Minum,Keluar'));
    });
    test('nama header alias, tanpa peka huruf', () {
      ok(p('DATE,TYPE,CATEGORY,AMOUNT,CURRENCY,NOTE\n$row'));
    });
    test('baris terakhir tanpa newline', () => ok(p('$_h\n$row')));
    test('jenis: sinonim', () {
      final r = p('$_h\n2026-01-01T00:00:00Z,income,Gaji,1,IDR,\n2026-01-01T00:00:00Z,MASUK,Gaji,1,IDR,');
      expect(r.records.map((e) => e.type), [TxType.income, TxType.income]);
    });
    test('emoji, non-Latin, baris baru di catatan', () {
      final r = p('$_h\n2026-01-01T00:00:00Z,Keluar,"Jajan 🍜",5000,IDR,"日本語\nbaris 2, ""kutip"""');
      expect(r.errors, isEmpty);
      expect(r.records.single.category, 'Jajan 🍜');
      expect(r.records.single.note, '日本語\nbaris 2, "kutip"');
    });
    test('UTF-8 dari byte, BOM dibuang', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('$_h\n$row')]);
      ok(parseTransactionCsvBytes(bytes));
    });
    test('nominal desimal sesuai mata uang', () {
      final r = p('$_h\n2026-01-01T00:00:00Z,Keluar,A,12.50,USD,\n2026-01-01T00:00:00Z,Keluar,A,12.5,USD,\n'
          '2026-01-01T00:00:00Z,Keluar,A,0.05,USD,\n2026-01-01T00:00:00Z,Keluar,A,500,JPY,\n2026-01-01T00:00:00Z,Keluar,A,10.00,IDR,');
      expect(r.errors, isEmpty);
      expect(r.records.map((e) => e.amountMinor), [1250, 1250, 5, 500, 10]);
    });
    test('titik koma: koma desimal diterima', () {
      final r = p('${_h.replaceAll(',', ';')}\n2026-01-01T00:00:00Z;Keluar;A;12,50;USD;');
      expect(r.records.single.amountMinor, 1250);
    });
    test('tanggal hanya hari -> tengah hari lokal', () {
      final x = p('$_h\n2026-03-05,Keluar,A,1,IDR,').records.single;
      expect(x.occurredAt, DateTime(2026, 3, 5, 12));
    });
    test('format ekspor LAMA (tanpa detik/zona, 6 kolom) tetap terbaca', () {
      final x = p('$_h\n2026-11-18 08:05,Keluar,Makan,12.50,USD,"kopi, ""enak"""').records.single;
      expect(x.occurredAt, DateTime(2026, 11, 18, 8, 5));
      expect(x.minutePrecision, isTrue);
      expect(x.amountMinor, 1250);
      expect(x.note, 'kopi, "enak"');
      expect(x.icon, isNull);
      expect(p('$_h\n2026-11-18T08:05:07+07:00,Keluar,A,1,IDR,').records.single.minutePrecision, isFalse);
    });
    test('ikon dan warna opsional', () {
      final r = p('$_h,Ikon,Warna\n2026-01-01T00:00:00Z,Keluar,A,1,IDR,,restaurant,#EF6C00\n'
          '2026-01-01T00:00:00Z,Keluar,B,1,IDR,,tidak-ada,zzz');
      expect(r.records[0].icon, 'restaurant');
      expect(r.records[0].color, 0xFFEF6C00);
      expect(r.records[1].icon, isNull);
      expect(r.records[1].color, isNull);
    });
  });

  group('galat per baris (nomor baris + kolom + alasan, baris valid tetap masuk)', () {
    test('beragam galat', () {
      final r = p('$_h\n'
          '2026-01-01T00:00:00Z,Keluar,A,1,IDR,ok\n' //                2 valid
          'bukan-tanggal,Keluar,A,1,IDR,\n' //                          3
          '2026-01-01T00:00:00Z,Transfer,A,1,IDR,\n' //                 4
          '2026-01-01T00:00:00Z,Keluar,,1,IDR,\n' //                    5
          '2026-01-01T00:00:00Z,Keluar,A,1,XYZ,\n' //                   6
          '2026-01-01T00:00:00Z,Keluar,A,abc,IDR,\n' //                 7
          '2026-01-01T00:00:00Z,Keluar,A,0,IDR,\n' //                   8
          '2026-01-01T00:00:00Z,Keluar,A,-5,IDR,\n' //                  9
          '2026-01-01T00:00:00Z,Keluar,A,12.345,USD,\n' //              10
          '2026-01-01T00:00:00Z,Keluar,A,1.5,IDR,\n' //                 11
          '2026-01-01T00:00:00Z,Keluar,A,"1.250,00",USD,\n' //          12
          '2026-01-01T00:00:00Z,Keluar,A,3,USD,fine');
      expect(r.records.length, 2);
      expect(r.totalRows, 12);
      final byLine = {for (final e in r.errors) e.line: e};
      expect(byLine.keys.toList()..sort(), [3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      expect(byLine[3]!.column, 'Tanggal');
      expect(byLine[4]!.column, 'Jenis');
      expect(byLine[5]!.column, 'Kategori');
      expect(byLine[6]!.column, 'Mata uang');
      expect(byLine[6]!.message, contains('XYZ'));
      expect(byLine[7]!.column, 'Nominal');
      expect(byLine[8]!.message, contains('lebih dari 0'));
      expect(byLine[10]!.message, contains('Tidak dibulatkan'));
      expect(byLine[11]!.message, contains('IDR'));
      expect(byLine[12]!.message, contains('pemisah ribuan'));
      expect(byLine[3]!.toString(), startsWith('Baris 3, kolom "Tanggal"'));
    });
    test('nomor baris benar setelah catatan multi-baris', () {
      final r = p('$_h\n2026-01-01T00:00:00Z,Keluar,A,1,IDR,"a\nb\nc"\nbad,Keluar,A,1,IDR,');
      expect(r.errors.single.line, 5, reason: 'record multi-baris memakai baris 2-4');
    });
    test('kategori terlalu panjang', () {
      expect(p('$_h\n2026-01-01T00:00:00Z,Keluar,${'x' * 41},1,IDR,').errors.single.column, 'Kategori');
    });
  });

  group('berkas bermasalah (galat jelas, tanpa crash)', () {
    test('kosong', () => expect(p('').fatal, contains('kosong')));
    test('hanya spasi/baris kosong', () => expect(p('\n\n  \n').fatal, isNotNull));
    test('hanya header', () => expect(p(_h).fatal, contains('hanya berisi header')));
    test('header tak dikenal', () {
      final r = p('foo,bar\n1,2');
      expect(r.fatal, contains('Kolom wajib'));
      expect(r.fatal, contains('Tanggal'));
    });
    test('bukan CSV (biner)', () => expect(p('PK\u0003\u0004\u0000\u0000data').fatal, contains('biner')));
    test('terlalu besar', () {
      final r = parseTransactionCsvBytes(Uint8List(TxCsv.maxBytes + 1));
      expect(r.fatal, contains('terlalu besar'));
    });
    test('byte rusak tidak melempar', () {
      expect(() => parseTransactionCsvBytes(Uint8List.fromList([0xFF, 0xFE, 0x41, 0x0A, 0xC3])), returnsNormally);
    });
  });

  group('penulis <-> pembaca (modul bersama)', () {
    test('perlindungan formula dibalik persis, termasuk awalan kutip tunggal', () {
      final notes = ["=1+1", "+62 812", "-diskon", "@user", "'=sudah-kutip", "''+dua", "'biasa", "a=b", "x'"];
      final recs = [
        for (final n in notes)
          TxCsvRecord(occurredAt: DateTime.utc(2026, 1, 1), type: TxType.expense, category: n, amountMinor: 1, currency: idr, note: n),
      ];
      final out = p(encodeTransactions(recs));
      expect(out.errors, isEmpty);
      expect(out.records.map((e) => e.note).toList(), notes);
      expect(out.records.map((e) => e.category).toList(), notes);
    });
    test('titik waktu persis (milidetik) dan nominal besar', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1790000000123, isUtc: true);
      final rec = TxCsvRecord(occurredAt: t, type: TxType.income, category: 'A', amountMinor: 999999999999999, currency: usd);
      final back = p(encodeTransactions([rec])).records.single;
      expect(back.occurredAt.millisecondsSinceEpoch, 1790000000123);
      expect(back.amountMinor, 999999999999999);
      expect(back.minutePrecision, isFalse);
    });
    test('template terbaca tanpa galat dan memakai header yang sama', () {
      final tpl = encodeTemplate(now: DateTime(2026, 11, 18));
      expect(tpl.split('\r\n').first, TxCsv.header.join(','));
      final r = p(tpl);
      expect(r.errors, isEmpty);
      expect(r.records.length, 2);
    });
  });
}
