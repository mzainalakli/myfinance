#!/usr/bin/env bash
# Menyiapkan tanda tangan rilis. Keystore + password dibuat di LUAR repo (default ~/myfinance-signing).
# Nilai rahasia tidak pernah dicetak.
#
#   bash tool/setup_signing.sh                 buat keystore (jika belum ada), tampilkan petunjuk
#   bash tool/setup_signing.sh --set-secrets   ...lalu isi 4 secret repo lewat gh (butuh gh login)
#   bash tool/setup_signing.sh --force-new     izinkan MENIMPA keystore lama (berbahaya: lihat peringatan)
set -euo pipefail

DIR="${MYFINANCE_SIGNING_DIR:-$HOME/myfinance-signing}"
JKS="$DIR/upload-keystore.jks"
ALIAS_NAME="upload"
SET_SECRETS=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --set-secrets) SET_SECRETS=1 ;;
    --force-new) FORCE=1 ;;
    *) echo "Argumen tidak dikenal: $a" >&2; exit 2 ;;
  esac
done

umask 077
mkdir -p "$DIR"; chmod 700 "$DIR"

if [ -e "$JKS" ] && [ "$FORCE" -ne 1 ]; then
  echo "Keystore sudah ada di $DIR -> dipakai ulang, TIDAK ditimpa."
  echo "(Keystore yang hilang/berubah = pembaruan tidak bisa dipasang di atas versi lama.)"
else
  if [ -e "$JKS" ]; then
    echo "PERINGATAN: --force-new menimpa keystore lama. Pembaruan atas versi yang sudah terpasang akan GAGAL." >&2
    mv "$JKS" "$JKS.bak.$(date +%s)"
  fi
  command -v keytool >/dev/null || { echo "keytool tidak ditemukan (pasang JDK)." >&2; exit 1; }
  # password acak (alfanumerik; aman untuk key.properties). Tidak dicetak.
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  export PASS
  printf '%s' "$PASS" > "$DIR/password.txt"
  printf '%s' "$ALIAS_NAME" > "$DIR/alias.txt"
  keytool -genkeypair -v -keystore "$JKS" -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$ALIAS_NAME" -storepass:env PASS -keypass:env PASS \
    -dname "CN=MyFinance, O=MyFinance, C=ID" >/dev/null 2>&1 \
    || { echo "keytool gagal." >&2; unset PASS; exit 1; }
  unset PASS
  chmod 600 "$JKS" "$DIR/password.txt" "$DIR/alias.txt"
  echo "Keystore baru dibuat. Isi disimpan di: $DIR  (jks, password.txt, alias.txt; izin 600)"
fi
# PKCS12: password toko kunci = password kunci -> satu password dipakai untuk keduanya.
base64 -w0 "$JKS" > "$DIR/keystore.base64"; chmod 600 "$DIR/keystore.base64"

cat <<MSG

================================ PENTING ================================
 CADANGKAN folder berikut di tempat aman DI LUAR komputer ini:
     $DIR
 Jika keystore/password hilang, pembaruan tidak bisa dipasang di atas
 versi lama (pengguna harus uninstall dan kehilangan data lokal).
 Jangan pernah commit folder ini atau menempelkan isinya ke chat/log.
=========================================================================
MSG

fill_manual() {
  cat <<'MSG'

Isi 4 secret secara manual: GitHub -> repo -> Settings -> Secrets and variables -> Actions -> New repository secret
  KEYSTORE_BASE64    = isi file  <folder>/keystore.base64   (satu baris)
  KEYSTORE_PASSWORD  = isi file  <folder>/password.txt
  KEY_ALIAS          = isi file  <folder>/alias.txt         (upload)
  KEY_PASSWORD       = isi file  <folder>/password.txt      (sama dengan KEYSTORE_PASSWORD)
Salin isi file lewat editor/clipboard; jangan ditampilkan di log. Setelah itu push ke main atau
jalankan workflow manual (Actions -> Build & Release APK -> Run workflow).
MSG
}

if [ "$SET_SECRETS" -ne 1 ]; then
  echo
  echo "Untuk mengisi secret otomatis lewat gh:  bash tool/setup_signing.sh --set-secrets"
  fill_manual
  exit 0
fi

if ! command -v gh >/dev/null || ! gh auth status >/dev/null 2>&1; then
  echo "gh belum terpasang/login -> isi secret manual, lalu hentikan di sini." >&2
  fill_manual
  exit 3
fi
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "Mengisi secret untuk repo: $REPO (nilai dibaca dari file, tidak ditampilkan)"
gh secret set KEYSTORE_BASE64   --repo "$REPO" < "$DIR/keystore.base64"
gh secret set KEYSTORE_PASSWORD --repo "$REPO" < "$DIR/password.txt"
gh secret set KEY_ALIAS         --repo "$REPO" < "$DIR/alias.txt"
gh secret set KEY_PASSWORD      --repo "$REPO" < "$DIR/password.txt"
echo "Selesai. Secret terdaftar:"; gh secret list --repo "$REPO" | cut -f1
