# Keputusan desain

- **Penamaan**: applicationId `app.myfinance` + paket Dart/Kotlin `myfinance` bersifat tetap. Nama tampilan
  hanya di 3 tempat (`strings.xml`, `AppConfig.appName`, `env.APP_FILE`). Lihat `docs/GANTI_NAMA.md`.
  Nama file DB (`myfinance.db`) dan kelas widget juga netral dan tidak ikut diganti.
- **Waktu**: `occurred_at`, `created_at`, `updated_at` = UTC epoch **milidetik** (integer). Pengelompokan hari memakai waktu lokal.
- **Numpad / input nominal** (menggantikan gaya mesin kasir sebelumnya): `AmountInput` (state-machine murni di
  `core/money/amount_input.dart`). Angka mengisi bagian bulat; desimal baru muncul setelah koma ditekan dan hanya
  untuk mata uang berdesimal (USD maks 2 digit, KWD 3). Tombol koma hanya ada bila mata uang punya desimal; untuk
  IDR/JPY slot itu diisi `000` (mata uang berdesimal tidak punya `000`, slotnya koma). `12,` tetap terlihat; simpan = 12,00.
  Awalan nol tidak menumpuk; bagian bulat maks 12 digit (12 × KWD 3 desimal = tepat `Money.maxMinor`).
  Ganti mata uang: bagian bulat dipertahankan, desimal berlebih dipotong. Konversi ke satuan terkecil tanpa double.
  Penyebab keluhan "mengetik 10 jadi 0,10": entri gaya kasir untuk mata uang berdesimal. Penentuan desimal IDR (0) dan
  default awal `IDR` sudah benar (diuji), jadi bukan bug di sumber desimal.
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
- **Logo** (Perbaikan 2): logo asli (koin putih + panah naik, tanpa teks) di `assets/branding/`; adaptive icon
  (background gradien, foreground, monokrom) lewat `flutter_launcher_icons` (dev dependency). `tool/make_icons.sh`
  = satu perintah (ikon + `ic_launcher_round` bulat). Foreground sengaja dibuat ±88% kanvas karena paket memberi inset 16%
  (simbol akhir ±60% kanvas adaptive, di dalam area aman 66%). Splash: latar polos `splash_bg` terang/gelap, Android 12+
  memakai ikon aplikasi. Pratinjau widget memakai `@mipmap/ic_launcher`. Lihat `docs/GANTI_LOGO.md`.
- **Sembunyikan saldo** (Perbaikan 3): status `balance_hidden` di shared_preferences, satu saklar untuk aplikasi dan widget.
  Topeng `••••••` (panjang tetap) lewat `Money.format/formatNumber(hidden:)` dan widget `MoneyText` (fade 150 ms,
  pembaca layar hanya membaca "Nominal disembunyikan"). Berlaku di kartu ringkasan (Beranda, Riwayat), legenda/total donat,
  tooltip tren; sumbu angka grafik dihilangkan saat tersembunyi (persentase tetap tampil). Ikon mata di kartu Beranda
  (+ ketuk angka) dan di judul Riwayat/Statistik. **Widget**: `WidgetService.buildPayload` (murni, teruji) mengirim
  topeng, bukan angka asli, dan `setBalanceHidden` langsung memperbarui widget. "Sembunyikan saat dibuka" diterapkan di
  `main()` (aplikasi utama saja) dengan menulis status ke prefs, supaya popup/widget konsisten dengan status efektif.
  "Sembunyikan nominal di riwayat" = nominal riwayat bertopeng hanya bila opsi aktif **dan** saldo sedang tersembunyi
  (ikon mata tetap saklar utama; lembar ubah transaksi selalu menampilkan angka). CSV tidak terpengaruh.
