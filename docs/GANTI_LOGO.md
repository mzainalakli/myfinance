# Mengganti logo

Logo terpisah dari nama aplikasi (tanpa teks di dalamnya), jadi mengganti nama tidak perlu logo baru.
Sumber logo ada di `assets/branding/` (PNG 1024x1024):

| File | Fungsi |
|---|---|
| `icon_background.png` | Layer latar adaptive icon (boleh warna polos/gradien) |
| `icon_foreground.png` | Layer simbol, latar transparan |
| `icon_monochrome.png` | Siluet untuk ikon bertema Android 13+ (alpha saja; warna diabaikan) |
| `icon.png` | Ikon penuh untuk Android < 8 (kotak membulat) |

## Memakai logo sendiri

1. Timpa keempat PNG di atas dengan logo Anda (ukuran 1024x1024).
2. Jalankan satu perintah:
   ```
   bash tool/make_icons.sh
   ```
   (menjalankan `dart run flutter_launcher_icons`, lalu membuat `ic_launcher_round`).
3. Build ulang (`flutter build apk`). Ikon launcher, ikon shortcut, pratinjau widget, dan splash Android 12+ ikut berubah.

## Aturan agar tidak terpotong

- `flutter_launcher_icons` memberi inset 16% pada foreground/monokrom. Karena itu simbol sebaiknya memenuhi
  ±85-90% kanvas PNG; hasil akhirnya ±60-65% dari kanvas adaptive, di dalam area aman (66% tengah).
- Foreground dan monokrom harus transparan di luar simbol.

## Menggambar ulang logo bawaan

`bash tool/make_icons.sh --redraw` menggambar ulang logo bawaan (koin + panah naik) lewat `tool/make_logo.py`
(perlu `pip install pillow`) lalu membangkitkan ikon. Ubah warna/bentuk di skrip itu bila perlu.

## Splash

Android 12+: ikon aplikasi di atas `splash_bg` (`res/values*/colors.xml`, terang/gelap).
Android lama: latar polos `splash_bg`, tanpa gambar. Tidak ada logo Flutter.
