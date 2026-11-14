#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${FACEPRINT_OUTPUT_APP:-$PWD/Faceprint.app}"
signing_identity="${FACEPRINT_SIGN_IDENTITY:--}"
if [[ ! -d Resources/ArcFace.mlmodelc ]]; then
    bash setup-resources.sh
fi
mkdir -p "$app/Contents/Helpers" "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/.build-cache"
sources=()
while IFS= read -r -d '' file; do sources+=("$file"); done < <(find Sources -name '*.swift' -print0)
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx15.0 \
    -module-cache-path "$PWD/.build-cache" "${sources[@]}" \
    -o "$app/Contents/MacOS/Faceprint"
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx15.0 \
    -module-cache-path "$PWD/.build-cache" Sources/UpdateCore.swift Tools/UpdateInstallerMain.swift \
    -o "$app/Contents/Helpers/FaceprintUpdateInstaller"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/ArcFace.mlmodelc "$app/Contents/Resources/"
cp Resources/*.mp4 Resources/*.png "$app/Contents/Resources/"
bash Branding/build-icon.sh
cp Branding/Faceprint.png "$app/Contents/Resources/FaceprintBrand.png"
cp Resources/Faceprint.icns "$app/Contents/Resources/"
cp LICENSE-Glance.txt "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign "$signing_identity" --identifier io.github.er1cg1ao.faceprint.updater \
    --options runtime "$app/Contents/Helpers/FaceprintUpdateInstaller"
codesign --force --sign "$signing_identity" --options runtime --entitlements entitlements.plist "$app"
codesign --verify --strict --deep "$app"
printf '%s\n' "Built $app"
