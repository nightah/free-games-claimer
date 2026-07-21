#!/usr/bin/env bash
# Install the Microsoft typefaces CloakBrowser checks for when spoofing Windows on Linux.
#
# CloakBrowser's dist/fonts.js probes for a specific set of Windows/Office faces; if they are
# missing it warns "Incomplete Windows font set" and the font fingerprint gives away that the
# host is Linux. These faces are proprietary and not available from apt (ttf-mscorefonts-installer
# only ships older XP-era fonts, not Segoe UI / Calibri / Consolas), so they are fetched from an
# archive of Windows font files.
#
# NOTE: these are proprietary Microsoft fonts redistributed without a stated licence. Installing
# them into an image you publish redistributes them. Set MS_FONTS=0 to skip this step.
#
# Source: https://github.com/pjobson/Microsoft-Fonts (archived)

set -eo pipefail

if [ "${MS_FONTS:-1}" != "1" ]; then
  echo "install-ms-fonts: MS_FONTS != 1, skipping Microsoft font install"
  exit 0
fi

REPO="https://raw.githubusercontent.com/pjobson/Microsoft-Fonts/main"
DEST="${MS_FONTS_DIR:-/usr/share/fonts/microsoft}"

# Exact files, pinned per family. Windows 11 is preferred and used wherever the face ships with
# it. The remaining faces (Century, Century Gothic, Book Antiqua, Bookman Old Style, Monotype
# Corsiva, MS Reference Specialty, MT Extra) are Microsoft *Office* fonts rather than Windows
# fonts, so they are absent from Windows 11 and are taken from the XP Media Center archive.
FILES=(
  # --- shipped with Windows 11 ---
  "2021 - Windows 11/ttf/Segoe UI - d9076ed73f2501090da92fe3c72d3ce6.ttf.gz"
  "2021 - Windows 11/ttf/Segoe UI Light - d44929d62a49114d494d1768893fcdf7.ttf.gz"
  "2021 - Windows 11/ttf/Calibri - 3dea6da513097358f7fbb4408aacb736.ttf.gz"
  "2021 - Windows 11/ttf/Consolas - 5715d3f0bfcd28a4e008721a66118fe2.ttf.gz"
  "2021 - Windows 11/ttf/Courier New - d8e98cd2725a3d8e80897fa55297dde0.ttf.gz"
  "2021 - Windows 11/ttf/Marlett - 21bf589620d6f89ef1bf31537dd7fde2.ttf.gz"
  # Windows ships "Franklin Gothic Medium"; there is no bare "Franklin Gothic" face.
  "2021 - Windows 11/ttf/Franklin Gothic Medium - 09aff291f163ebea6a3fc9e98ee3281d.ttf.gz"
  # Called out by CloakBrowser's font-setup notes alongside Segoe UI and Calibri.
  "2021 - Windows 11/ttf/Bahnschrift - 551f5d12731d3747e5182bd3e8a7683c.ttf.gz"
  # --- Office-era faces, not present in Windows 11 ---
  "2002 - Windows XP Media Center Edition/ttf/Century Gothic - cfce6abbbff0099b15691345d8b94dcc.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/Century - 28806fbbd48444f22edee13bddeef650.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/Book Antiqua - 3efd8e6a45b3f893f54399c6bf4aba68.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/Bookman Old Style - 4267d8aa8711bb8c72cbefb26066c9e0.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/Monotype Corsiva - b98f57ac686fc135914a844ec0ce8d49.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/MS Reference Specialty - da7d0632677782c7c4dd8b201ce85a8f.ttf.gz"
  "2002 - Windows XP Media Center Edition/ttf/MT Extra - e269de5f63fcdedca11755947615f1fb.ttf.gz"
  # MS UI Gothic has no standalone file - it is a face inside the MS Gothic TrueType Collection.
  "2021 - Windows 11/ttc/MS Gothic - 9e83607a5bcbdd23c24276545f7304a2.ttc.gz"
)

mkdir -p "$DEST"

# percent-encode a path for the raw.githubusercontent URL (spaces and other unsafe chars)
urlencode() {
  local s="$1" out="" c
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      /) out+="/" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

for f in "${FILES[@]}"; do
  # strip the " - <md5>" suffix and the .gz so the installed file keeps a clean name
  name="$(basename "$f" .gz)"
  name="$(printf '%s' "$name" | sed -E 's/ - [0-9a-f]{32}\././')"
  echo "install-ms-fonts: fetching ${name}"
  curl -fsSL "${REPO}/$(urlencode "$f")" | gunzip > "${DEST}/${name}"
done

fc-cache -f >/dev/null
echo "install-ms-fonts: installed ${#FILES[@]} font files into ${DEST}"
