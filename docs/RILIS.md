# Rilis APK otomatis

Setiap push ke `main` (selain perubahan `*.md` / `docs/**`) menjalankan `.github/workflows/release.yml`:
analyze → test → build APK rilis bertanda tangan → **verifikasi** → tag `vX.Y.Z.N` → GitHub Release (Latest) berisi 3 APK.
`X.Y.Z` dari `version:` di `pubspec.yaml`, `N` = nomor run (juga jadi `versionCode`, selalu naik).
Nama file: `myfinance-vX.Y.Z.N-<abi>.apk`.

## Pengaman di workflow (gagal otomatis bila...)

- secret keystore kosong, atau keystore/alias tidak bisa dibuka;
- APK tidak berjumlah 3, verifikasi `apksigner` gagal, **sertifikat bertanda "Android Debug"**, atau sertifikat antar-APK berbeda;
- `applicationId` bukan `app.myfinance`, atau APK meminta izin `INTERNET`;
- tag yang akan dibuat sudah ada (tidak pernah menimpa rilis lama).
Keystore dan `key.properties` dihapus di akhir job (`if: always()`).

## Penyiapan satu kali

```
bash tool/setup_signing.sh                 # buat keystore + password acak di ~/myfinance-signing (di luar repo, izin 600)
bash tool/setup_signing.sh --set-secrets   # isi 4 secret repo lewat gh (perlu `gh auth login`)
```
Skrip tidak mencetak nilai rahasia dan menolak menimpa keystore yang ada (kecuali `--force-new`, berbahaya).
Tanpa `gh`, isi manual: **Settings → Secrets and variables → Actions** → `KEYSTORE_BASE64` (isi `keystore.base64`),
`KEYSTORE_PASSWORD` dan `KEY_PASSWORD` (isi `password.txt`), `KEY_ALIAS` (isi `alias.txt`, yaitu `upload`).
Pengaturan repo: **Settings → Actions → General** harus mengizinkan Actions dan *Workflow permissions* boleh menulis
(workflow sudah meminta `contents: write`).

> ⚠️ **Cadangkan folder `~/myfinance-signing` di tempat aman di luar komputer ini.** Bila keystore atau password hilang,
> pembaruan tidak bisa dipasang di atas versi lama (pengguna harus uninstall dan kehilangan data lokal).

## Merilis versi baru

- Push ke `main` otomatis membuat rilis baru. Untuk perubahan besar, naikkan `version:` di `pubspec.yaml`
  (mis. `1.1.0+1`); bagian `+n` diabaikan, nomor build diambil dari nomor run.
- Manual: **Actions → Build & Release APK → Run workflow**, atau `gh workflow run release.yml`.
- Pantau: `gh run watch`, gagal: `gh run view --log-failed`.
- Perubahan hanya di `*.md`/`docs/**` tidak memicu rilis.

## Aturan agar pembaruan selalu bisa dipasang di atas versi lama

- Selalu pakai keystore yang sama (sidik jari sertifikat rilis pertama: SHA-256 `396d08e4…6d94829`).
- `applicationId` (`app.myfinance`) tidak boleh berubah. Nama tampilan boleh: lihat `GANTI_NAMA.md`.

## Peralihan sekali: dari APK debug/uji ke APK rilis resmi

APK debug (atau APK rilis lokal bertanda debug) yang pernah terpasang memakai tanda tangan **berbeda** dari APK rilis resmi.
Android menolak menimpanya, jadi saat pertama memasang APK rilis resmi: **ekspor CSV dulu** (Pengaturan → Ekspor semua data),
uninstall aplikasi lama (data lokal hilang), lalu pasang APK rilis. Setelah itu pembaruan berikutnya terpasang langsung di atasnya.
