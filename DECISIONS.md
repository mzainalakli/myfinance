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
- **Impor CSV**: format ekspor/impor didefinisikan satu kali di `core/csv/transaction_csv.dart`.
  **Format ekspor diubah ke v2** karena v1 lossy: tanggal `yyyy-MM-dd HH:mm` lokal tanpa detik/zona tidak bisa dipulihkan ke
  detik yang sama. v2 = ISO 8601 lokal + milidetik + offset, plus kolom opsional Ikon/Warna. v1 tetap terbaca (header dikenali
  lewat nama; tanggal tanpa zona = waktu lokal perangkat).
  Pelindung formula-injection dibuat bolak-balik persis: awalan `'` ditambahkan bila sel (setelah nol atau lebih `'`) diawali
  `= + - @ TAB CR`, dan dibuang tepat satu kali saat impor (v1 ambigu untuk catatan yang memang diawali `'`).
  **Deduplikasi** = multiset atas (waktu, jenis, nominal, mata uang, kategori, catatan): n kembar di berkas dan m di DB
  -> tambah max(0, n-m). Baris dari berkas v1 (tanpa detik) dicocokkan per menit. Nominal dengan desimal berlebih = galat
  (sisa nol seperti `10.00` untuk IDR diterima karena tidak membulatkan). Mode **Ganti semua** menghapus transaksi saja
  (kategori, templates, pengaturan tetap) dan menulis cadangan CSV ke `<support dir>/backups/` sebelum menghapus.
  Penulisan dalam satu transaksi drift (rollback penuh bila gagal, termasuk kategori baru). `created_at/updated_at` = waktu impor.
  Tanpa perubahan skema DB. Pemilih file: `file_picker` (SAF, tanpa izin penyimpanan); parsing di isolate (`compute`).
- **Kelola kategori (Perbaikan #2-1)**. *Investigasi*: repository sudah punya `updateCategory`/`setArchived`/`reorderCategories`
  dan layar sudah bisa ketuk-untuk-edit, tetapi **tidak ada hapus**, tidak ada validasi (nama kembar lolos, bahkan antar kategori bawaan
  dan hasil impor jadi ambigu), tidak ada larangan kategori terakhir, tidak ada pindah transaksi, jenis tidak bisa diubah, dan UI hanya
  satu daftar bercampur dengan tombol arsip bolak-balik. Jadi kekurangannya di **repository dan UI**, bukan hanya UI.
  *Aturan*: kunci pencocokan nama = `categoryKey(jenis, trim+huruf kecil)` di `repository.dart`, dipakai validasi **dan** impor CSV
  (satu aturan). Kategori terarsip ikut dihitung saat cek kembar (kalau tidak, impor akan mendapat dua kandidat). Semua operasi
  kategori berjalan dalam satu transaksi DB dan melempar `CategoryException` dengan kode (UI menerjemahkan ke teks).
  Jenis hanya boleh diubah bila belum ada transaksi/templat; jenis berubah = kategori masuk di akhir urutan jenis baru.
  **Hapus**: tanpa transaksi -> hapus permanen + Urungkan (`DeletedCategory` menyimpan baris & templat). Dengan transaksi -> sheet:
  *Arsipkan* (disarankan) atau *Pindahkan* (`moveTransactionsAndDelete`, atomik; templat ikut dipindah). Tidak ada opsi hapus-beserta-transaksi.
  Kategori aktif terakhir per jenis tidak bisa dihapus/diarsipkan/dipindah jenis (terarsip tidak dihitung sebagai pemilih).
  Tabel `templates` belum dipakai UI mana pun dan widget/popup tidak menyimpan id kategori, jadi rujukan hanya perlu dijaga di DB
  (dipindah saat pindah; templat ikut dihapus bila kategorinya dihapus; arsip tidak menyentuh templat). Tanpa perubahan skema.
  Tes fixture impor yang sebelumnya menambah kategori kembar kini memakai kategori bawaan yang sama.
- **FAB vs filter (Perbaikan #2-2)**. *Investigasi (dari kode, belum dilihat di HP)*: hanya `AppShell` yang memiliki FAB (`endFloat`,
  di atas bar navigasi), jadi tampil di Beranda, Riwayat, Statistik. Kelola Kategori adalah rute di luar shell: **tidak ada FAB**.
  Tumpang tindih: `FilterBar` (chip periode + tombol filter) berada di dasar kolom Riwayat dan Statistik, tepat di strip tempat FAB
  melayang, di ukuran apa pun (lebih parah di 360 dp dan teks besar karena FAB "Catat" ±138 dp). Statistik juga menaruh tombol
  segmen Keluar/Masuk di dasar, ikut tertutup. Beranda: tombol "Riwayat" selebar layar di ujung daftar, bisa di bawah FAB di layar pendek.
  **Pola yang dipilih (semua layar)**: kontrol *tidak pernah* di dasar layar; filter periode (dan segmen Statistik) menempel
  tetap di bawah judul halaman, dan hanya daftar yang bergulir di dasar. Daftar memberi `Tk.fabClearance` (88 = 56 + 16 + 16)
  di bawah. FAB menyusut ke ikon saat menggulir ke bawah (`isExtended`), kembali saat menggulir ke atas atau saat gulir benar-benar
  berhenti (`ScrollEndNotification`; `idle` pada `UserScrollNotification` diabaikan karena itu hanya jari terangkat saat fling);
  gulir mendatar (chip) diabaikan. Snackbar mengambang otomatis di atas FAB karena semua pesan lewat Scaffold milik shell.
  FAB mengecil sampai hilang saat keyboard terbuka; sheet modal menutupinya lewat penghalang.
  *Batas tes*: pada posisi gulir awal dengan data banyak, baris daftar yang sedang bergulir pasti ada di bawah FAB (itu sifat
  daftar); yang diuji di posisi awal adalah semua tombol/chip, dan baris ikut diuji di posisi akhir serta pada data sedikit.
  `test/fab_overlap_test.dart` (3 layar × 2 ukuran × 2 skala teks × 2 jumlah data) gagal pada tata letak lama (diverifikasi: 8 galat).
  *Bug tambahan yang ditemukan tes*: `bottomNavigationBar` berisi `Align` (via `ContentWidth`) membentang setinggi layar dan
  menghabiskan ruang daftar; di Kelola Kategori kini memakai `Center(heightFactor: 1)`.
- **Kegagalan CI `fab_overlap_test` (data sedikit, /history 360x640, teks x1.3)**: penyebab = tes, bukan aplikasi. Data uji dibuat
  dengan `now - i*7 jam`; di runner CI (UTC, ~04:34) transaksi kedua jatuh ke hari sebelumnya, sehingga muncul header hari
  tambahan dan baris kedua terdorong ke jalur FAB (tinggi daftar bergantung pada jam dan zona waktu mesin, tidak pernah gagal di
  WIB lokal). Perbaikan: data uji kini terikat ke tengah hari lokal (data sedikit = satu hari), jadi deterministik. Assertion tidak
  dilonggarkan. Tes kinerja tidak gagal di CI (parse 115 ms vs batas 3000 ms, dst.; margin sudah >10x), jadi batasnya tidak diubah.
