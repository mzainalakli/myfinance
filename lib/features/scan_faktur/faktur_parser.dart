import 'dart:convert';

/// Parser murni QR kiri faktur elektronik Taiwan (電子發票證明聯). Tanpa dependensi UI, tidak melempar.
/// Spesifikasi dan keputusan: DECISIONS.md ("Scan faktur").

class FakturItem {
  final String nama;
  final double jumlah;
  final double harga;
  const FakturItem(this.nama, this.jumlah, this.harga);
}

class FakturData {
  /// 2 huruf besar + 8 digit, tanpa strip (mis. `HB35094463`).
  final String nomorFaktur;

  /// Hanya tanggal (tengah malam lokal). Jam tidak ada di QR.
  final DateTime tanggal;
  final String kodeAcak;

  /// Total termasuk pajak, dalam NT$ bulat (kolom posisi 29–36).
  final int totalNt;
  final String npwpPenjual;
  final String npwpPembeli;

  /// Kosong bila tak ada, tak terbaca, atau berencoding Big5.
  final List<FakturItem> daftarBarang;
  const FakturData({
    required this.nomorFaktur,
    required this.tanggal,
    required this.kodeAcak,
    required this.totalNt,
    required this.npwpPenjual,
    required this.npwpPembeli,
    this.daftarBarang = const [],
  });
}

enum FakturGagalAlasan { bukanFaktur, qrKananTerdeteksi, formatRusak }

sealed class FakturResult {
  const FakturResult();
}

class FakturOk extends FakturResult {
  final FakturData data;
  const FakturOk(this.data);
}

class FakturGagal extends FakturResult {
  final FakturGagalAlasan alasan;

  /// Penjelasan teknis singkat (untuk log/tes), bukan untuk ditampilkan mentah.
  final String detail;
  const FakturGagal(this.alasan, this.detail);
}

const kFakturPanjangTetap = 77;

final _awalFaktur = RegExp(r'^[A-Za-z]{2}\d{8}\d{7}');
final _hex8 = RegExp(r'^[0-9A-Fa-f]{8}$');
final _digit8 = RegExp(r'^\d{8}$');

FakturResult parseFaktur(String raw) {
  final s = raw.trim();
  if (s.startsWith('**')) {
    return const FakturGagal(FakturGagalAlasan.qrKananTerdeteksi, 'diawali **');
  }
  // Tidak berawalan seperti faktur sama sekali -> QR lain (URL, teks, dll.).
  if (!_awalFaktur.hasMatch(s)) {
    return FakturGagal(FakturGagalAlasan.bukanFaktur, 'tidak berawalan nomor faktur + tanggal');
  }
  FakturGagal rusak(String d) => FakturGagal(FakturGagalAlasan.formatRusak, d);
  if (s.length < kFakturPanjangTetap) return rusak('panjang ${s.length} < $kFakturPanjangTetap');

  final nomor = s.substring(0, 10).toUpperCase();
  final tanggal = _tanggalMinguo(s.substring(10, 17));
  if (tanggal == null) return rusak('tanggal tidak valid');
  final acak = s.substring(17, 21);
  final totalHex = s.substring(29, 37);
  if (!_hex8.hasMatch(s.substring(21, 29)) || !_hex8.hasMatch(totalHex)) return rusak('heksadesimal tidak valid');
  final total = int.parse(totalHex, radix: 16);
  if (total <= 0) return rusak('total nol');
  final npwpPembeli = s.substring(37, 45);
  final npwpPenjual = s.substring(45, 53);
  if (!_digit8.hasMatch(npwpPenjual)) return rusak('NPWP penjual bukan 8 digit');
  if (!_digit8.hasMatch(npwpPembeli)) return rusak('NPWP pembeli bukan 8 digit');

  return FakturOk(FakturData(
    nomorFaktur: nomor,
    tanggal: tanggal,
    kodeAcak: acak,
    totalNt: total,
    npwpPenjual: npwpPenjual,
    npwpPembeli: npwpPembeli,
    daftarBarang: _barang(s.substring(kFakturPanjangTetap)),
  ));
}

/// `yyyMMdd` tahun Minguo (ROC) -> tanggal Masehi (yyy + 1911); null bila bukan tanggal kalender nyata.
DateTime? _tanggalMinguo(String s) {
  if (!RegExp(r'^\d{7}$').hasMatch(s)) return null;
  final y = int.parse(s.substring(0, 3)) + 1911;
  final m = int.parse(s.substring(3, 5));
  final d = int.parse(s.substring(5, 7));
  final t = DateTime(y, m, d);
  return t.year == y && t.month == m && t.day == d ? t : null;
}

/// Bagian opsional: `:` + 10 karakter area bebas + `:jml_di_qr:jml_total:encoding:nama:jumlah:harga...`.
/// Segala kegagalan di sini menghasilkan daftar kosong, tidak pernah menggagalkan parsing inti.
List<FakturItem> _barang(String rest) {
  try {
    if (rest.length < 12 || rest[0] != ':' || rest[11] != ':') return const [];
    final f = rest.substring(12).split(':');
    if (f.length < 3) return const [];
    final enc = f[2];
    if (enc != '1' && enc != '2') return const []; // 0 = Big5: tanpa dependensi tambahan, dilewati
    final out = <FakturItem>[];
    for (var i = 3; i + 2 < f.length; i += 3) {
      final nama = enc == '2' ? utf8.decode(base64.decode(base64.normalize(f[i])), allowMalformed: false) : f[i];
      final jumlah = double.tryParse(f[i + 1]);
      final harga = double.tryParse(f[i + 2]);
      if (nama.trim().isEmpty || jumlah == null || harga == null) continue;
      out.add(FakturItem(nama.trim(), jumlah, harga));
    }
    return out;
  } catch (_) {
    return const [];
  }
}
