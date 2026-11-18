# Update terkini: MyFinance

> **Perbaikan #1 (3 commit)** dicatat di bagian "Perbaikan #1" di bawah.

Ringkasan kondisi aplikasi saat dokumen ini ditulis (18 Nov 2026).
Dokumen lain: `RILIS.md` (rilis APK), `GANTI_NAMA.md` (ganti nama tampilan), `../DECISIONS.md` (keputusan desain).

## Status per fase

| Fase | Isi | Status |
|---|---|---|
| 1. Fondasi | Proyek, tema + token, drift + migrasi, `Money`, repository, tes | Kode selesai, `analyze` dan tes lolos |
| 2. Catat + riwayat | Sheet catat + numpad, riwayat, edit/hapus/undo, pengaturan | Kode selesai, `analyze` lolos |
| 3. Filter + rekap + statistik | Filter gabungan, rekap per mata uang, 3 grafik, CSV | Kode selesai, `analyze` dan tes lolos |
| 4. Widget + popup + shortcut | `QuickAddActivity`, widget 2 layout, shortcuts | Kode selesai, terkompilasi; **belum diuji di perangkat** |
| 5. Actions + rilis | `release.yml`, penandatanganan, dokumen | Berkas selesai, **belum dijalankan di GitHub** |
| 6. Pemolesan | Uji layar, ukuran APK, mode gelap, 10.000 transaksi | Hanya uji 10.000 transaksi (otomatis) dan cek izin/ukuran APK |

## Build (terverifikasi 18 Nov 2026)

- `flutter build apk --debug`: **berhasil**.
- `flutter build apk --release --split-per-abi`: **berhasil** (R8 + shrinkResources aktif; ditandatangani debug
  karena `key.properties` tidak ada, sesuai rencana untuk build lokal).
  arm64-v8a 23,9 MB, armeabi-v7a 21,6 MB, x86_64 25,4 MB.
- Manifest APK rilis: **tanpa izin `INTERNET`**. Izin yang ada berasal dari plugin `home_widget` (WorkManager):
  `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`.
- `applicationId` `app.myfinance`, label `MyFinance`, targetSdk 36.
- Peringatan build: `home_widget` memakai Kotlin Gradle Plugin lama (hanya peringatan, bukan galat).

## Yang belum terverifikasi

- Belum ada uji di perangkat/emulator: popup, widget, shortcut, tampilan 360x640, mode gelap, tablet,
  dan "tiga ketukan" dari widget. Kode Kotlin sudah terkompilasi, tetapi perilakunya belum dilihat.
- Ukuran APK (±24 MB) belum dianalisis; kemungkinan besar mesin Flutter + SQLite + font. Belum dicari penghematan.
- Workflow GitHub belum pernah berjalan; secret keystore belum diisi.
- Kinerja scroll daftar 10.000 baris di HP belum diukur.

## Perbaikan #1 (dari pemakaian nyata di HP)

1. **Input nominal natural** (`0135d0b`): `AmountInput` (state-machine murni). `1`,`0` → `10`; `000` → `10.000`;
   desimal baru muncul setelah koma, tombol koma hanya untuk mata uang berdesimal (IDR/JPY: slot itu `000`);
   `12,` tetap terlihat; awalan nol tidak menumpuk; backspace hapus koma; tahan = kosongkan; maks 12 digit bulat;
   ganti mata uang mempertahankan bagian bulat. 26 tes. Soal "desimal muncul di IDR": penentuan desimal IDR (0) dan default
   `IDR` diperiksa dan benar (diuji); keluhan berasal dari entri gaya kasir untuk mata uang berdesimal.
2. **Logo** (`7898410`): logo asli (koin + panah naik, tanpa teks), adaptive icon (latar gradien, foreground, monokrom),
   `ic_launcher_round`, splash tanpa logo Flutter (latar terang/gelap; Android 12+ memakai ikon aplikasi), pratinjau widget.
   Dibangkitkan dengan `bash tool/make_icons.sh`; panduan `docs/GANTI_LOGO.md`.
   Terverifikasi: manifest APK memakai `res/mipmap-anydpi-v26/ic_launcher.xml` (adaptive + monochrome), simbol di area aman
   (±60% kanvas), pratinjau PNG dilihat. Bug yang ditemukan dan diperbaiki: inset 16% dari `flutter_launcher_icons` membuat simbol terlalu kecil.
3. **Sembunyikan saldo**: ikon mata, topeng di aplikasi dan di data widget, status tersimpan, dua opsi di Pengaturan.
   Tes: pemformat `hidden`, persistensi (termasuk "aplikasi ditutup"), `buildPayload` widget tanpa digit saat tersembunyi.

**Belum bisa diverifikasi tanpa HP:** tampilan ikon di launcher (bentuk bulat/squircle, tema monokrom Android 13+),
splash Android 12+ dan mode gelap, perilaku widget (topeng muncul/hilang saat ikon mata diketuk, rendering topeng di
widget kecil), numpad di layar kecil (tombol koma, 4 tombol terakhir), pembaca layar (TalkBack), dan fade 150 ms.

## Hasil tes otomatis (`flutter test`: 70 lolos)

- `money_test`: format, parse, desimal per mata uang (IDR 0, USD 2, KWD 3), bolak-balik tanpa kehilangan presisi.
- `data_test`: seed/migrasi, filter gabungan, kata kunci (`%`, `_` literal), arsip kategori, urutan frekuensi, hapus + urungkan, rekap per mata uang.
- `stats_csv_test`: rincian kategori, batang bulanan, tren kumulatif, CSV (escape, anti injeksi rumus).
- `amount_input_test`: input nominal IDR/USD/JPY/KWD, batas, ganti mata uang.
- `privacy_test`: topeng, persistensi status, payload widget, `MoneyText`.
- `performance_test`: 10.000 transaksi di SQLite memori (mode JIT): ambil semua baris ±160 ms,
  hitung statistik ±210 ms, filter kata kunci ±6 ms. Ini bukan ukuran di HP; kinerja daftar (scroll) belum diuji.
- Catatan: `schemaVersion` masih 1, jadi tes migrasi baru mencakup pembuatan awal + buka ulang, belum jalur `onUpgrade`.

## Penamaan (sesuai aturan terbaru)

- Nama tampilan **MyFinance** ada di 3 tempat: `res/values/strings.xml` (`app_name`), `lib/core/app_config.dart`
  (`AppConfig.appName`), `env.APP_FILE` di `release.yml`.
- `applicationId` = `app.myfinance`, paket Dart/Kotlin = `myfinance`. Tetap, jangan diubah.
- `docs/GANTI_NAMA.md` sudah ditulis.

## Fitur yang sudah ada di kode

- Catat: toggle Keluar/Masuk, chip kategori urut frekuensi, catatan, nominal + mata uang, Simpan di atas numpad kustom
  (ikon kalender kecil di baris catatan untuk tanggal; lihat DECISIONS).
- Beranda (ringkasan bulan ini per mata uang, 5 terbaru), Riwayat (per hari, geser ubah/hapus, undo),
  Statistik (donat, batang, garis), filter bottom sheet + chip periode, ekspor CSV (filter/semua).
- Pengaturan: mata uang/jenis default, tema, format angka; kelola kategori (tambah, ubah, urut, arsip).
- Android: popup transparan `QuickAddActivity` (entrypoint `quickAddMain`), widget `+ Keluar` / `+ Masuk` + total hari ini,
  shortcut tekan-lama, DB bersama (WAL + `busy_timeout`), R8 minify + shrinkResources di rilis.

## Belum dikerjakan (pasca-MVP, sesuai spesifikasi)

Template transaksi + widget sekali ketuk, backup/restore JSON, kurs manual, anggaran per kategori.
Tabel `templates` sudah ada di skema.

## Langkah berikutnya

1. Coba di emulator/HP: popup, widget, shortcut, 360x640, mode gelap; ukur scroll 10.000 baris.
2. Periksa ukuran APK.
3. Buat keystore + secret (lihat `RILIS.md`), push ke `main`, pastikan tag `vX.Y.Z.N` dan 3 APK terbentuk.
