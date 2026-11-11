#!/bin/sh
# Copies docs/screenshot.png into the website as an optimised WebP plus PNG fallback
# and writes its real size into index.html. Needs cwebp (brew install webp) and sips (macOS).
set -eu
cd "$(dirname "$0")/.."
src=docs/screenshot.png
[ -f "$src" ] || { echo "missing $src"; exit 1; }
w=$(sips -g pixelWidth "$src" | awk '/pixelWidth/{print $2}')
h=$(sips -g pixelHeight "$src" | awk '/pixelHeight/{print $2}')
if [ "$w" -gt 2400 ]; then
  sips -Z 2400 "$src" --out site/assets/screenshot.png >/dev/null
else
  cp "$src" site/assets/screenshot.png
fi
cwebp -quiet -q 85 site/assets/screenshot.png -o site/assets/screenshot.webp
w=$(sips -g pixelWidth site/assets/screenshot.png | awk '/pixelWidth/{print $2}')
h=$(sips -g pixelHeight site/assets/screenshot.png | awk '/pixelHeight/{print $2}')
sed -i '' -E "s#(src=\"assets/screenshot.png\"[^>]*) width=\"[0-9]+\" height=\"[0-9]+\"#\1 width=\"$w\" height=\"$h\"#" site/index.html
ls -l site/assets/screenshot.png site/assets/screenshot.webp
echo "screenshot: ${w}x${h}"
