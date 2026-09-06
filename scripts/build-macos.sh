#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
build_root="$repository_root/artifacts/macos"
app="$build_root/Momo Memo.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

clang \
  "$repository_root/MomoMemoMac/Sources/main.m" \
  -fobjc-arc \
  -framework Cocoa \
  -mmacosx-version-min=13.0 \
  -O2 \
  -o "$app/Contents/MacOS/MomoMemo"

cp "$repository_root/MomoMemoMac/Info.plist" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"

echo "$app"
