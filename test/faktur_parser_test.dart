import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfinance/features/scan_faktur/faktur_parser.dart';

void main() {
  const sample =
      'HB35094463115111713430000005F000000640000000027258805Zm9vYmFyYmF6cXV4MTIzNDU2:**********:1:1:1:Kopi:1:100';
  // 77 karakter inti dengan bagian yang bisa diganti
  String core({
    String no = 'HB35094463',
    String date = '1151117',
    String rand = '1343',
    String sales = '0000005F',
    String total = '00000064',
    String buyer = '00000000',
    String seller = '27258805',
    String enc = 'Zm9vYmFyYmF6cXV4MTIzNDU2',
  }) =>
      '$no$date$rand$sales$total$buyer$seller$enc';

  FakturData ok(String s) {
    final r = parseFaktur(s);
    expect(r, isA<FakturOk>(), reason: r is FakturGagal ? '${r.alasan} ${r.detail}' : '');
    return (r as FakturOk).data;
  }

  FakturGagalAlasan gagal(String s) {
    final r = parseFaktur(s);
    expect(r, isA<FakturGagal>());
    return (r as FakturGagal).alasan;
  }

  test('panjang inti persis 77', () => expect(core().length, 77));

  test('vektor uji dari spesifikasi', () {
    final d = ok(sample);
    expect(d.nomorFaktur, 'HB35094463');
    expect(d.tanggal, DateTime(2026, 11, 17));
    expect(d.kodeAcak, '1343');
    expect(d.totalNt, 100);
    expect(d.npwpPenjual, '27258805');
    expect(d.npwpPembeli, '00000000');
    expect(d.daftarBarang.length, 1);
    expect(d.daftarBarang.first.nama, 'Kopi');
    expect(d.daftarBarang.first.jumlah, 1);
    expect(d.daftarBarang.first.harga, 100);
  });

  test('total memakai kolom total (29-36), bukan penjualan sebelum pajak', () {
    expect(ok(core(sales: '00000005', total: '000003E8')).totalNt, 1000);
  });

  test('hanya 77 karakter tanpa barang tetap valid', () {
    final d = ok(core());
    expect(d.daftarBarang, isEmpty);
    expect(d.totalNt, 100);
  });

  test('encoding Base64 (UTF-8 dibungkus Base64)', () {
    final nama = base64.encode(utf8.encode('茶葉蛋'));
    final d = ok('${core()}:**********:1:1:2:$nama:2:15');
    expect(d.daftarBarang.single.nama, '茶葉蛋');
    expect(d.daftarBarang.single.jumlah, 2);
    expect(d.daftarBarang.single.harga, 15);
  });

  test('encoding UTF-8 dengan beberapa barang dan harga desimal', () {
    final d = ok('${core()}:**********:2:2:1:茶葉蛋:1:10:牛奶:2:35.5');
    expect(d.daftarBarang.map((e) => e.nama), ['茶葉蛋', '牛奶']);
    expect(d.daftarBarang.last.harga, 35.5);
  });

  test('encoding Big5: barang kosong, parsing inti tetap sukses', () {
    final d = ok('${core()}:**********:1:1:0:Kopi:1:100');
    expect(d.daftarBarang, isEmpty);
    expect(d.totalNt, 100);
  });

  test('barang rusak tidak menggagalkan parsing inti', () {
    expect(ok('${core()}:**********:1:1:2:%%%bukan-base64%%%:1:100').daftarBarang, isEmpty);
    expect(ok('${core()}:xx').daftarBarang, isEmpty);
    expect(ok('${core()}:**********:1:1:1:Kopi:abc:100').daftarBarang, isEmpty);
    expect(ok('${core()}:**********:1:1:1:Kopi:1').daftarBarang, isEmpty, reason: 'triplet tak lengkap dibuang');
  });

  test('QR kanan terdeteksi', () {
    expect(gagal('**Tea:1:50:Coke:1:30'), FakturGagalAlasan.qrKananTerdeteksi);
    expect(gagal('  **abc'), FakturGagalAlasan.qrKananTerdeteksi);
  });

  test('bukan faktur', () {
    expect(gagal('https://example.com/promo'), FakturGagalAlasan.bukanFaktur);
    expect(gagal(''), FakturGagalAlasan.bukanFaktur);
    expect(gagal('x' * 200), FakturGagalAlasan.bukanFaktur);
  });

  test('terlalu pendek: berawalan faktur = rusak, selain itu bukan faktur', () {
    expect(gagal(core().substring(0, 60)), FakturGagalAlasan.formatRusak);
    expect(gagal('12345'), FakturGagalAlasan.bukanFaktur);
  });

  test('tanggal tidak valid', () {
    expect(gagal(core(date: '1151317')), FakturGagalAlasan.formatRusak, reason: 'bulan 13');
    expect(gagal(core(date: '1150230')), FakturGagalAlasan.formatRusak, reason: '30 Februari');
    expect(gagal(core(date: '1150229')), FakturGagalAlasan.formatRusak, reason: '2026 bukan kabisat');
    expect(gagal(core(date: '1151100')), FakturGagalAlasan.formatRusak, reason: 'hari 0');
    expect(ok(core(date: '1130229')).tanggal, DateTime(2024, 2, 29), reason: '2024 kabisat');
  });

  test('heksadesimal tidak valid', () {
    expect(gagal(core(total: '0000006G')), FakturGagalAlasan.formatRusak);
    expect(gagal(core(sales: 'ZZZZZZZZ')), FakturGagalAlasan.formatRusak);
  });

  test('huruf kecil pada nomor faktur dinormalkan ke huruf besar', () {
    expect(ok(core(no: 'hb35094463')).nomorFaktur, 'HB35094463');
  });

  test('nomor faktur bukan 2 huruf + 8 digit', () {
    expect(gagal(core(no: 'H335094463')), FakturGagalAlasan.bukanFaktur);
    expect(gagal(core(no: 'HB3509446X')), FakturGagalAlasan.bukanFaktur);
  });

  test('spasi dan baris baru di ujung dibuang', () {
    expect(ok('\n  $sample \r\n').nomorFaktur, 'HB35094463');
  });

  test('total nol ditolak', () {
    expect(gagal(core(total: '00000000')), FakturGagalAlasan.formatRusak);
  });

  test('NPWP penjual/pembeli harus 8 digit', () {
    expect(gagal(core(seller: '2725880A')), FakturGagalAlasan.formatRusak);
    expect(gagal(core(buyer: '0000000X')), FakturGagalAlasan.formatRusak);
  });

  test('konversi tahun Minguo di sekitar batas', () {
    expect(ok(core(date: '1131231')).tanggal, DateTime(2024, 12, 31));
    expect(ok(core(date: '1150101')).tanggal, DateTime(2026, 1, 1));
    expect(ok(core(date: '0010101')).tanggal, DateTime(1912, 1, 1));
  });

  test('total heksadesimal besar tetap benar', () {
    expect(ok(core(total: '000F4240')).totalNt, 1000000);
    expect(ok(core(total: '00000064'.toLowerCase())).totalNt, 100);
    expect(ok(core(total: '0000abcd')).totalNt, 0xABCD);
  });
}
