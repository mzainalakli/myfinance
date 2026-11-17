# Keputusan desain

- **Penamaan**: applicationId `app.myfinance` + paket Dart/Kotlin `myfinance` bersifat tetap. Nama tampilan
  hanya di 3 tempat (`strings.xml`, `AppConfig.appName`, `env.APP_FILE`). Lihat `docs/GANTI_NAMA.md`.
  Nama file DB (`myfinance.db`) dan kelas widget juga netral dan tidak ikut diganti.
- **Waktu**: `occurred_at`, `created_at`, `updated_at` = UTC epoch **milidetik** (integer). Pengelompokan hari memakai waktu lokal.
- **Numpad**: nominal = integer satuan terkecil. Tiap angka digeser masuk dari kanan (gaya mesin kasir):
  IDR/JPY mengetik rupiah/yen langsung; USD mengetik sen (1-2-5-0 → 12,50). Tombol `000` menambah tiga nol.
  Batas maksimum `Money.maxMinor` agar aman di int 64-bit.
- **Money & format angka**: format/parse buatan sendiri (bukan `NumberFormat`) agar deterministik dan teruji;
  gaya `1.234,56` (id) atau `1,234.56` (en) dipilih di Pengaturan. Simbol dipisah NBSP.
- **Rekap**: `summarize()` selalu mengelompokkan per kode mata uang; `Money +` melempar galat bila beda mata uang.
- **Filter bersama**: satu `filterProvider` untuk Riwayat dan Statistik. Periode cepat dihitung saat kueri (aman lewat tengah malam).
  Kata kunci memakai `LIKE` dengan escape (`%`/`_` huruf biasa).
- **Statistik**: dihitung di Dart dari baris terfilter (10.000 baris ≈ 200 ms mode JIT). Grafik memerlukan satu mata uang,
  dipilih lewat chip (default: yang transaksinya terbanyak). Nilai `double` hanya untuk sumbu grafik, bukan penyimpanan.
  Tren = selisih kumulatif dalam periode terfilter (mulai 0), diringkas ≤ 60 titik.
- **Kategori**: "hapus" = arsip (`is_archived`). Transaksi lama tetap utuh. Urutan lewat drag.
- **Tanggal di sheet**: ikon kalender kecil di baris catatan (di luar daftar 6 elemen) agar bisa mencatat mundur dan mengedit tanggal.
- **Keyboard**: saat kolom catatan fokus, numpad/nominal disembunyikan dan tombol berubah "Selesai" agar tidak overflow.
- **Database bersama**: satu file `myfinance.db`; popup berjalan di engine Flutter lain (isolate lain, koneksi sendiri).
  WAL + `busy_timeout=5000` mencegah konflik. Aplikasi utama memanggil `refreshAll()` saat resume agar stream menangkap tulisan popup.
- **Popup**: `QuickAddActivity` (FlutterActivity transparan, `quickAddMain`), rute awal `/quick/<type>`, `excludeFromRecents`, task sendiri.
- **Widget**: hanya tombol + ringkasan hari ini (mata uang default; mata uang lain diberi catatan "+n"). Data basi (hari kemarin)
  tampil 0. Dua layout (compact/wide) dipilih dari lebar widget. Warna ikut tema sistem lewat `values-night`.
- **Migrasi**: `schemaVersion = 1` dengan kerangka `onUpgrade`. Tabel `templates` sudah ada untuk fitur pasca-MVP.
- **Paket tambahan**: `path`, `path_provider` (lokasi DB & berkas sementara CSV), `flutter_localizations` (SDK; date picker bahasa Indonesia).
  `sqlite3_flutter_libs` tidak dipakai (EOL); `sqlite3` v3 membundel SQLite lewat build hook.
- **Font**: Inter Regular/Medium/Bold dibundel (lisensi OFL di `assets/fonts`).
- **Tidak ada izin INTERNET** di manifest utama (hanya manifest debug/profile bawaan Flutter yang punya, untuk hot reload).
