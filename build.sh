#!/bin/zsh
# Still.app をビルドする（Xcode 不要。Command Line Tools の swiftc だけで作る）
#   ./build.sh           build/Still.app を作る
#   ./build.sh install   作ったうえで /Applications に入れて起動する
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Still.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# アイコン：各サイズをそのピクセル数で直接描いて .icns にする（縮小しないのでにじまない）
ICONSET=build/AppIcon.iconset
swift tools/make-icon.swift "$ICONSET" >/dev/null
cp "$ICONSET/icon_512x512@2x.png" Resources/icon-preview.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# 本体：サイズ優先で最適化し、使わないコードとシンボルを落とす
swiftc -Osize -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
  -Xlinker -dead_strip Sources/*.swift -o "$APP/Contents/MacOS/Still"
strip -x "$APP/Contents/MacOS/Still"

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier io.github.darthreidar-jp.still "$APP" >/dev/null
echo "built: $PWD/$APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == install ]]; then
  pkill -x Still 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/Still.app
  ditto "$APP" /Applications/Still.app
  open /Applications/Still.app
  echo "installed: /Applications/Still.app"
fi
