#!/usr/bin/env bash
#
# runtalya foto/ içindeki görselleri yaris2.JPG ile aynı piksel ölçüsüne getirir.
# Yaklaşım: Oranı koru (cover) -> ortadan kırp (center crop).
# Orijinallere dokunmaz; çıktıları yeni klasöre yazar.
#
# Kullanım:
#   ./scripts/normalize_runtalya_photos_to_yaris2.sh
#   ./scripts/normalize_runtalya_photos_to_yaris2.sh "runtalya foto" "yaris2.JPG"
#

set -euo pipefail

SRC_DIR="${1:-runtalya foto}"
REF_NAME="${2:-yaris2.JPG}"
REF_PATH="${SRC_DIR}/${REF_NAME}"

if [ ! -d "$SRC_DIR" ]; then
  echo "Hata: Klasör bulunamadı: $SRC_DIR" >&2
  exit 1
fi

if [ ! -f "$REF_PATH" ]; then
  echo "Hata: Referans görsel bulunamadı: $REF_PATH" >&2
  exit 1
fi

read_dim() {
  local f="$1"
  local w h line
  # sips -1 tek satır döndürüyor:
  # /path/file.jpg|pixelWidth: 6419|pixelHeight: 4281|
  line="$(sips -g pixelWidth -g pixelHeight -1 "$f" 2>/dev/null || true)"
  read -r w h < <(
    printf "%s\n" "$line" \
      | sed -E 's/.*pixelWidth: ([0-9]+).*pixelHeight: ([0-9]+).*/\1 \2/'
  )
  if [[ -z "${w}" || -z "${h}" || "${w}" = "0" || "${h}" = "0" ]]; then
    return 1
  fi
  echo "${w} ${h}"
}

read -r TARGET_W TARGET_H < <(read_dim "$REF_PATH")
OUT_DIR="${SRC_DIR}/normalized_${TARGET_W}x${TARGET_H}"
mkdir -p "$OUT_DIR"

echo "Hedef: ${TARGET_W}×${TARGET_H}"
echo "Kaynak: $SRC_DIR"
echo "Çıktı:  $OUT_DIR"
echo ""

shopt -s nullglob 2>/dev/null || true

count=0
skipped=0

for f in "$SRC_DIR"/*.png "$SRC_DIR"/*.PNG "$SRC_DIR"/*.jpg "$SRC_DIR"/*.jpeg "$SRC_DIR"/*.JPG "$SRC_DIR"/*.JPEG; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"

  # Referansı da çıktı klasörüne kopyala (yeniden encode etmeden)
  if [ "$f" = "$REF_PATH" ]; then
    cp -p "$f" "$OUT_DIR/$name"
    count=$((count + 1))
    continue
  fi

  if ! read -r W H < <(read_dim "$f"); then
    echo "Atlandı (ölçü okunamadı): $name"
    skipped=$((skipped + 1))
    continue
  fi

  # Cover ölçek: her iki boyut da hedefi karşılasın
  read -r NEW_W NEW_H < <(
    W="$W" H="$H" TARGET_W="$TARGET_W" TARGET_H="$TARGET_H" python3 - <<'PY'
import math, os, sys
w = int(os.environ["W"])
h = int(os.environ["H"])
tw = int(os.environ["TARGET_W"])
th = int(os.environ["TARGET_H"])
scale = max(tw / w, th / h)
nw = int(math.ceil(w * scale))
nh = int(math.ceil(h * scale))
print(nw, nh)
PY
  )

  tmp="$OUT_DIR/.tmp_${name}"
  out="$OUT_DIR/$name"

  echo "İşleniyor: $name (${W}×${H}) -> cover ${NEW_W}×${NEW_H} -> crop ${TARGET_W}×${TARGET_H}"

  # 1) Oranı koruyarak cover olacak şekilde yeniden örnekle
  # 2) Ortadan hedef ölçüye kırp
  #
  # Not: sips JPEG yeniden kodlayacağı için matematiksel olarak "kayıpsız" olamaz;
  # formatOptions=best ile kaliteyi maksimumda tutuyoruz.
  sips -z "$NEW_H" "$NEW_W" "$f" --out "$tmp" >/dev/null
  sips -s formatOptions best -c "$TARGET_H" "$TARGET_W" "$tmp" --out "$out" >/dev/null
  rm -f "$tmp"

  count=$((count + 1))
done

echo ""
echo "Tamamlandı: $count dosya -> $OUT_DIR"
if [ $skipped -ne 0 ]; then
  echo "Atlanan: $skipped"
fi

