#!/usr/bin/env bash
# App Store Connect – Ekran görüntülerini iPhone 6.5" kabul edilen boyuta (1284×2778 px) resize eder.
# Kullanım: ./resize_screenshots_for_appstore.sh [kaynak_klasör]
# Örnek:   ./resize_screenshots_for_appstore.sh ~/Desktop/screenshots

set -e

# App Store iPhone 6.5" Display kabul edilen boyutlar (dikey)
WIDTH=1284
HEIGHT=2778

if [ -z "$1" ]; then
  echo "Kullanım: $0 <kaynak_klasör>"
  echo "Örnek:   $0 ~/Desktop/screenshots"
  echo ""
  echo "Kaynak klasördeki PNG/JPEG dosyaları ${WIDTH}×${HEIGHT} px boyutuna getirilir"
  echo "ve aynı klasörün altına 'appstore_${WIDTH}x${HEIGHT}' içine yazılır."
  exit 1
fi

SRC_DIR="$1"
OUT_DIR="${SRC_DIR}/appstore_${WIDTH}x${HEIGHT}"

if [ ! -d "$SRC_DIR" ]; then
  echo "Hata: Klasör bulunamadı: $SRC_DIR"
  exit 1
fi

mkdir -p "$OUT_DIR"
count=0

# Eşleşmeyen glob'lar boş genişlesin (literal * kalmasın)
shopt -s nullglob 2>/dev/null || true

for f in "$SRC_DIR"/*.png "$SRC_DIR"/*.PNG "$SRC_DIR"/*.jpg "$SRC_DIR"/*.jpeg "$SRC_DIR"/*.JPG "$SRC_DIR"/*.JPEG; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  out="$OUT_DIR/$name"
  echo "Resize: $name -> ${WIDTH}×${HEIGHT}"
  sips -z $HEIGHT $WIDTH "$f" --out "$out"
  count=$((count + 1))
done

if [ $count -eq 0 ]; then
  echo "Kaynak klasörde PNG/JPEG dosyası bulunamadı: $SRC_DIR"
  rmdir "$OUT_DIR" 2>/dev/null || true
  exit 1
fi

echo ""
echo "Tamamlandı: $count dosya -> $OUT_DIR"
echo "Bu görselleri App Store Connect'te iPhone 6.5\" Display alanına yükleyebilirsiniz."
