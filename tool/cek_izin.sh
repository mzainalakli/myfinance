#!/usr/bin/env bash
# Memeriksa izin pada manifest HASIL MERGE (bukan hanya AndroidManifest.xml proyek) dari APK yang sudah dibangun.
# Pemakaian: bash tool/cek_izin.sh [path.apk ...]   (tanpa argumen: semua build/app/outputs/flutter-apk/app-*-release.apk)
# Lulus bila: ada CAMERA, tidak ada INTERNET. Izin lain dicetak untuk ditinjau.
set -euo pipefail
AAPT2="$(command -v aapt2 || true)"
if [ -z "$AAPT2" ] && [ -n "${ANDROID_HOME:-}" ]; then
  AAPT2="$(ls -d "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -n "$AAPT2" ] || { echo "aapt2 tidak ditemukan (pasang Android build-tools / set ANDROID_HOME)"; exit 2; }
if [ "$#" -gt 0 ]; then apks=("$@"); else
  shopt -s nullglob; apks=(build/app/outputs/flutter-apk/app-*-release.apk)
fi
[ "${#apks[@]}" -gt 0 ] || { echo "Tidak ada APK rilis. Jalankan: flutter build apk --release --split-per-abi"; exit 2; }
fail=0
for apk in "${apks[@]}"; do
  perms="$("$AAPT2" dump permissions "$apk")"
  echo "== $(basename "$apk")"; echo "$perms"
  if echo "$perms" | grep -q "android.permission.INTERNET"; then echo "GAGAL: ada INTERNET"; fail=1; fi
  if ! echo "$perms" | grep -q "android.permission.CAMERA"; then echo "GAGAL: tidak ada CAMERA"; fail=1; fi
  "$AAPT2" dump xmltree --file AndroidManifest.xml "$apk" | grep -A2 "uses-feature" | grep -E "camera|required" || true
done
[ "$fail" -eq 0 ] && echo "OK: CAMERA ada, INTERNET tidak ada" || exit 1
