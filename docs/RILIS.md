# Rilis APK otomatis

Setiap push ke `main` membangun APK rilis bertanda tangan, membuat tag `vX.Y.Z.N`
(`X.Y.Z` dari `pubspec.yaml`, `N` = nomor run GitHub Actions) dan melampirkan 3 APK ke Release.

## Langkah satu kali (pemilik repo)

1. Buat keystore:
   ```
   keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Ubah ke base64 lalu salin hasilnya: `base64 -w0 upload-keystore.jks` (Linux).
3. Di repo GitHub: **Settings → Secrets and variables → Actions**, tambahkan:
   `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
4. **Cadangkan file `.jks` dan passwordnya di tempat aman di luar repo.**
   Jika hilang, pembaruan tidak bisa dipasang di atas versi lama.
5. Unduh APK dari halaman **Releases**. Pilih `arm64-v8a` untuk hampir semua HP modern
   (`armeabi-v7a` untuk HP lama 32-bit, `x86_64` untuk emulator).

Bila secret `KEYSTORE_BASE64` kosong, workflow berhenti dengan galat (tidak pernah merilis APK
bertanda debug). Secret tidak dicetak ke log.

## Aturan agar pembaruan selalu bisa dipasang di atas versi lama

- Selalu pakai keystore yang sama.
- `applicationId` (`app.myfinance`) tidak boleh berubah. Nama tampilan boleh: lihat `GANTI_NAMA.md`.
- `versionCode` = nomor run, selalu naik.
