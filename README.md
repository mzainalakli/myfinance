# MyFinance

Pencatatan keuangan pribadi yang ringan, offline, dan minimalis untuk Android. Tanpa akun, tanpa internet.
(Nama tampilan sementara; cara menggantinya: `docs/GANTI_NAMA.md`.)

## Unduh dan pasang

1. Buka **https://github.com/mzainalakli/myfinance/releases/latest** di HP.
2. Unduh **`myfinance-…-arm64-v8a.apk`** (untuk hampir semua HP Android modern). HP lama 32-bit: `armeabi-v7a`;
   emulator PC: `x86_64`.
3. Buka berkas yang diunduh. Jika diminta, izinkan **"Pasang aplikasi dari sumber tidak dikenal"** untuk browser/penyimpan
   berkas yang dipakai (Pengaturan → Aplikasi → *Akses khusus* → *Pasang aplikasi tak dikenal*; lokasi menu beda tiap merek).
4. Pembaruan: unduh rilis terbaru dan pasang di atas yang lama (data tetap, selama berasal dari rilis resmi).

Catatan: bila sebelumnya memasang APK debug/uji, aplikasi itu harus di-uninstall sekali (lihat `docs/RILIS.md`).

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
