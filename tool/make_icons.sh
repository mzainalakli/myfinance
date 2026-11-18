#!/usr/bin/env bash
# Satu perintah: bangkitkan semua ikon dari assets/branding/*.png
#   bash tool/make_icons.sh            (setelah menimpa PNG sumber dengan logo Anda)
#   bash tool/make_icons.sh --redraw   (gambar ulang logo bawaan lebih dulu; perlu Pillow)
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${1:-}" = "--redraw" ] && python3 tool/make_logo.py
dart run flutter_launcher_icons
python3 tool/make_round_icons.py
