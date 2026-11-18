# Format CSV transaksi (ekspor dan impor)

Satu-satunya definisi format: `lib/core/csv/transaction_csv.dart` (penulis, pembaca, template). Ekspor dan impor memakai
modul yang sama, jadi tidak mungkin berbeda diam-diam. Tes: `test/transaction_csv_test.dart`, `test/import_service_test.dart`.

## Format yang ditulis (ekspor, v2)

Berkas UTF-8 **dengan BOM**, akhir baris `\r\n`, pemisah koma, header di baris pertama:

```
Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan,Ikon,Warna
2026-11-18T08:05:07.123+07:00,Keluar,Makan & Minum,18000,IDR,Kopi,restaurant,#EF6C00
2026-11-01T09:00:00.000+07:00,Masuk,Gaji,1500.00,USD,"Bonus, ""tahunan""",salary,#43A047
```

| Kolom | Isi |
|---|---|
| `Tanggal` | ISO 8601 waktu lokal + milidetik + offset (`yyyy-MM-ddTHH:mm:ss.SSS+hh:mm`): menunjuk detik yang persis sama setelah diimpor |
| `Jenis` | `Masuk` atau `Keluar` |
| `Kategori` | nama kategori |
| `Nominal` | desimal bertitik, tanpa pemisah ribuan, tepat sebanyak desimal mata uang (IDR/JPY 0, USD 2, KWD 3), tidak pernah dibulatkan; selalu > 0 |
| `Mata uang` | kode ISO 4217 (harus ada di daftar bawaan) |
| `Catatan` | teks bebas, boleh berisi koma, kutip, baris baru, emoji |
| `Ikon`, `Warna` | opsional: kunci ikon kategori dan `#RRGGBB`. Dipakai hanya bila kategori baru dibuat |

Kutip & escape: kolom berisi `"`, `,` atau baris baru dikutip dengan `"…"`; `"` ditulis `""`.

**Perlindungan formula-injection:** kolom `Kategori` dan `Catatan` yang (setelah nol atau lebih `'`) diawali `=`, `+`, `-`, `@`,
TAB atau CR diberi awalan `'`. Pembaca membuang tepat satu `'` bila sel cocok pola itu, sehingga bolak-balik persis
(termasuk catatan yang memang diawali `'`).

## Yang dibaca (impor)

- Kolom dikenali lewat **nama header** (tidak peka huruf, spasi/`_`/`-` diabaikan), bukan posisi. Kolom tambahan diabaikan,
  urutan bebas. Alias: `Date`/`Waktu`, `Type`/`Tipe`, `Category`, `Amount`/`Jumlah`, `Currency`/`Mata_uang`, `Note`/`Keterangan`,
  `Icon`, `Color`. Wajib: tanggal, jenis, kategori, nominal, mata uang.
- BOM UTF-8, `\r\n`/`\n`/`\r`, pemisah **koma, titik koma, atau tab** (dideteksi dari header), kolom berkutip, baris baru di dalam kolom.
- `Jenis`: `Masuk`/`Keluar` (juga `income`/`expense`, `pemasukan`/`pengeluaran`).
- `Tanggal`: ISO 8601 dengan offset atau `Z`; atau tanpa zona (`2026-11-18 08:05`, dianggap waktu lokal perangkat); atau hanya
  tanggal (jadi pukul 12.00 lokal).
- `Nominal`: titik sebagai desimal. Bila pemisah berkas `;`, `12,50` juga diterima. Desimal melebihi batas mata uang = galat
  (kecuali sisa nol, mis. `10.00` untuk IDR). Pemisah ribuan = galat. Nominal harus > 0.
- Berkas > 25 MB, kosong, hanya header, header tak dikenal, atau berisi byte biner ditolak dengan pesan jelas.

## Kompatibilitas dengan ekspor lama (v1)

v1: `Tanggal,Jenis,Kategori,Nominal,Mata uang,Catatan` dengan tanggal `yyyy-MM-dd HH:mm` (waktu lokal, **tanpa detik dan zona**).
Berkas v1 tetap bisa diimpor. Karena detiknya hilang, deduplikasi untuk baris tanpa detik mencocokkan **per menit**.
(Perubahan v2 memperbaiki hal ini: v1 tidak bisa dipulihkan ke detik yang sama dan ambigu bila zona waktu berbeda.)

## Aturan impor ke database

- **Kategori**: dicocokkan lewat nama + jenis (tak peka huruf, spasi pinggir dipangkas); kategori terarsip yang cocok dipakai
  kembali. Yang belum ada dibuat (ikon/warna dari berkas bila ada, jika tidak `more` + warna dari palet).
- **Duplikat**: sidik jari = waktu + jenis + nominal + mata uang + nama kategori + catatan, dicocokkan **berbasis jumlah**:
  n kembar di berkas dan m di database → hanya `max(0, n − m)` ditambahkan. Impor ulang tidak menggandakan data; dua transaksi
  yang memang kembar tetap dua.
- **Gabungkan** (default): tambah yang belum ada. **Ganti semua**: cadangan CSV data sekarang disimpan lebih dulu di penyimpanan
  privat aplikasi, lalu semua transaksi dihapus dan diisi dari berkas. Kategori dan pengaturan tidak dihapus.
- Seluruh penulisan dalam satu transaksi database (atomik). Baris tak valid dilewati dan dilaporkan.
- `created_at`/`updated_at` diisi waktu impor (tidak diekspor).
