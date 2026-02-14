#!/usr/bin/env bash
# Google Play – Özellik grafiğini (Feature Graphic) 1024×500 px boyutuna getirir.
# Gereksinim: 1024×500 px, PNG veya JPEG, en fazla 15 MB.
# Kullanım: ./resize_feature_graphic_for_google_play.sh [kaynak_dosya_veya_klasör]
# Örnek:   ./resize_feature_graphic_for_google_play.sh ~/Desktop/feature.png
# Örnek:   ./resize_feature_graphic_for_google_play.sh ~/Desktop/graphics

set -e

# Google Play Özellik grafiği gereksinimi
WIDTH=1024
HEIGHT=500

if [ -z "$1" ]; then
  echo "Kullanım: $0 <kaynak_dosya_veya_klasör>"
  echo "Örnek:   $0 ~/Desktop/feature.png"
  echo "Örnek:   $0 ~/Desktop/graphics"
  echo ""
  echo "Görsel(ler) ${WIDTH}×${HEIGHT} px (özellik grafiği) boyutuna getirilir."
  echo "Google Play: PNG veya JPEG, en fazla 15 MB."
  exit 1
fi

SRC="$1"

process_file() {
  local f="$1"
  local out_dir="$2"
  [ -f "$f" ] || return 1
  local name=$(basename "$f")
  local out="$out_dir/$name"
  echo "Resize: $name -> ${WIDTH}×${HEIGHT}"
  sips -z $HEIGHT $WIDTH "$f" --out "$out"
  return 0
}

count=0

if [ -f "$SRC" ]; then
  # Tek dosya
  SRC_DIR=$(dirname "$SRC")
  OUT_DIR="${SRC_DIR}/google_play_feature_${WIDTH}x${HEIGHT}"
  mkdir -p "$OUT_DIR"
  if process_file "$SRC" "$OUT_DIR"; then
    count=1
  fi
elif [ -d "$SRC" ]; then
  # Klasör
  OUT_DIR="${SRC}/google_play_feature_${WIDTH}x${HEIGHT}"
  mkdir -p "$OUT_DIR"
  shopt -s nullglob 2>/dev/null || true
  for f in "$SRC"/*.png "$SRC"/*.PNG "$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.JPG "$SRC"/*.JPEG; do
    process_file "$f" "$OUT_DIR" && count=$((count + 1))
  done
else
  echo "Hata: Dosya veya klasör bulunamadı: $SRC"
  exit 1
fi

if [ $count -eq 0 ]; then
  echo "İşlenecek PNG/JPEG dosyası bulunamadı."
  [ -d "$OUT_DIR" ] && rmdir "$OUT_DIR" 2>/dev/null || true
  exit 1
fi

echo ""
echo "Tamamlandı: $count dosya -> $OUT_DIR"
echo "Bu görseli Google Play Console'da Özellik grafiği alanına yükleyebilirsiniz (1024×500 px, max 15 MB)."
