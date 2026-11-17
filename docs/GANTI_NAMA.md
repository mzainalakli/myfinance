# Mengganti nama aplikasi

Ada dua hal berbeda:

| Hal | Nilai awal | Boleh diganti? |
|---|---|---|
| Nama tampilan (label ikon, judul, nama file APK) | `MyFinance` | **Ya, kapan saja** |
| `applicationId` (identitas internal Android) | `app.myfinance` | **TIDAK** |

> ⚠️ **Jangan mengubah `applicationId`** (di `android/app/build.gradle.kts`), nama paket Dart
> (`name:` di `pubspec.yaml`), maupun paket Kotlin `app.myfinance`. Android menganggap
> applicationId baru sebagai aplikasi lain, sehingga pembaruan tidak bisa dipasang di atas versi lama.

## Nama tampilan: ubah tepat 3 tempat

1. `android/app/src/main/res/values/strings.xml` → `app_name`
   (dipakai manifest, widget, dan shortcut lewat `@string/app_name`).
2. `lib/core/app_config.dart` → `AppConfig.appName`
   (dipakai semua judul di UI, awalan nama file CSV, dan popup).
3. `.github/workflows/release.yml` → `env.APP_FILE`
   (nama file APK dan judul rilis; huruf kecil tanpa spasi).

Selesai. Tidak ada tempat lain yang perlu disentuh.
