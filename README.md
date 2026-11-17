# MyFinance

Pencatatan keuangan pribadi yang ringan, offline, dan minimalis untuk Android. Tanpa akun, tanpa internet.
(Nama tampilan sementara; cara menggantinya: `docs/GANTI_NAMA.md`.)

## Cara pakai

- **Catat**: tombol **Catat** (kanan bawah), atau widget layar utama (**+ Keluar / + Masuk**),
  atau tekan lama ikon aplikasi. Pilih kategori, ketik nominal di numpad, **Simpan**.
- **Riwayat**: dikelompokkan per hari. Geser ke kanan untuk ubah, ke kiri untuk hapus (bisa diurungkan).
  Chip periode dan tombol filter ada di bawah. Ikon bagikan di atas mengekspor CSV sesuai filter.
- **Statistik**: donat per kategori, batang per bulan, tren selisih. Mengikuti filter yang sama; per satu mata uang.
- **Pengaturan** (ikon di Beranda): mata uang/jenis default, tema, format angka, kelola kategori, ekspor semua.
- Rekap selalu terpisah per mata uang; tidak ada konversi kurs.

## Membangun

Butuh Flutter stable, JDK 17+, Android SDK.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # hanya bila mengubah tabel drift
flutter analyze && flutter test
flutter build apk --debug
```

Rilis bertanda tangan dibuat otomatis oleh GitHub Actions: lihat `docs/RILIS.md`.

## Struktur

```
lib/core/        tema + token, Money, database (drift), util, string
lib/features/    transactions, stats, settings, widget
android/         Kotlin: popup (QuickAddActivity), widget, shortcut
docs/            RILIS.md, GANTI_NAMA.md
```

Keputusan desain: `DECISIONS.md`.
