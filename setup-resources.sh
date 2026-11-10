#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
glance_app="${1:-/Applications/Glance.app}"
source_resources="$glance_app/Contents/Resources"
if [[ ! -d "$source_resources/ArcFace.mlmodelc" ]]; then
    printf '%s\n' 'Install Glance first, or pass its app path to this script.' >&2
    printf '%s\n' 'Upstream: https://github.com/jonnyoo/glance' >&2
    exit 1
fi
mkdir -p Resources
cp -R "$source_resources/ArcFace.mlmodelc" Resources/
for asset in unlockanimation.mp4 unsuccessfulunlockanimation.mp4 unlockstatic.png; do
    cp "$source_resources/$asset" Resources/
done
printf '%s\n' 'Imported the ArcFace model and animation assets from your local Glance installation.'
printf '%s\n' 'Review THIRD_PARTY_NOTICES.md for code, media, and model terms.'
