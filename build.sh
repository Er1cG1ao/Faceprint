#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/Faceprint.app"
if [[ ! -d Resources/ArcFace.mlmodelc ]]; then
    bash setup-resources.sh
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/.build-cache"
sources=()
while IFS= read -r -d '' file; do sources+=("$file"); done < <(find Sources -name '*.swift' -print0)
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx15.0 \
    -module-cache-path "$PWD/.build-cache" "${sources[@]}" \
    -o "$app/Contents/MacOS/Faceprint"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/ArcFace.mlmodelc "$app/Contents/Resources/"
cp Resources/*.mp4 Resources/*.png "$app/Contents/Resources/"
bash Branding/build-icon.sh
cp Resources/Faceprint.icns "$app/Contents/Resources/"
cp LICENSE-Glance.txt "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
xattr -cr "$app"
if ! codesign --force --sign - --options runtime --entitlements entitlements.plist "$app"; then
    xattr -cr "$app"
    codesign --force --sign - --options runtime --entitlements entitlements.plist "$app"
fi
printf '%s\n' "Built $app"
