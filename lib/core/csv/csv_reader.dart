/// Pembaca CSV tingkat rendah (RFC 4180 + toleransi): BOM, CRLF/LF/CR, kolom berkutip, kutip ganda
/// ter-escape, baris baru di dalam kolom, pemisah koma / titik koma / tab.
class CsvRecord {
  /// Nomor baris fisik (mulai 1) tempat record dimulai, untuk pesan galat.
  final int line;
  final List<String> fields;
  const CsvRecord(this.line, this.fields);
}

class CsvTable {
  final String delimiter;
  final List<CsvRecord> records;

  /// Terisi bila ada kutip yang tidak tertutup (file rusak).
  final String? error;
  const CsvTable(this.delimiter, this.records, {this.error});
}

String detectDelimiter(String text) {
  var comma = 0, semi = 0, tab = 0;
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      inQ = !inQ;
    } else if (!inQ) {
      if (c == '\n' || c == '\r') {
        if (comma + semi + tab > 0) break; // baris pertama yang berisi saja (header)
      } else if (c == ',') {
        comma++;
      } else if (c == ';') {
        semi++;
      } else if (c == '\t') {
        tab++;
      }
    }
  }
  if (semi > comma && semi >= tab) return ';';
  if (tab > comma && tab > semi) return '\t';
  return ',';
}

CsvTable readCsv(String input, {String? delimiter}) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final d = delimiter ?? detectDelimiter(text);
  final records = <CsvRecord>[];
  var fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  var quoted = false;
  var line = 1;
  var recLine = 1;

  void endField() {
    var v = sb.toString();
    if (!quoted) v = v.trim();
    fields.add(v);
    sb.clear();
    quoted = false;
  }

  void endRecord() {
    endField();
    final blank = fields.length == 1 && fields[0].isEmpty && !quoted;
    if (!blank) records.add(CsvRecord(recLine, fields));
    fields = <String>[];
  }

  final n = text.length;
  for (var i = 0; i < n; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        if (c == '\n') line++;
        sb.write(c);
      }
      continue;
    }
    if (quoted && (c == ' ' || c == '\t') && c != d) {
      continue; // spasi setelah kutip penutup diabaikan
    }
    if (c == '"' && !quoted && sb.toString().trim().isEmpty) {
      sb.clear();
      inQuotes = true;
      quoted = true;
    } else if (c == d) {
      endField();
    } else if (c == '\r') {
      if (i + 1 < n && text[i + 1] == '\n') i++;
      endRecord();
      line++;
      recLine = line;
    } else if (c == '\n') {
      endRecord();
      line++;
      recLine = line;
    } else {
      sb.write(c);
    }
  }
  if (inQuotes) {
    return CsvTable(d, records, error: 'Tanda kutip dibuka di baris $recLine tetapi tidak pernah ditutup.');
  }
  if (sb.isNotEmpty || fields.isNotEmpty || quoted) endRecord();
  return CsvTable(d, records);
}
