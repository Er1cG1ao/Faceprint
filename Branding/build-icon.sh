#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
iconset=$(mktemp -d /tmp/faceprint-icon.XXXXXX)
trap 'rm -rf "$iconset"' EXIT
for size in 16 32 128 256 512 1024; do
    sips -z "$size" "$size" Branding/Faceprint.png --out "$iconset/icon_${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Branding/Faceprint.png --out "$iconset/icon_${size}@2x.png" >/dev/null
done
# PNG-backed ICNS elements, including each standard and Retina size.
python3 - "$iconset" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
slots = [('icp4','16'),('icp5','32'),('icp6','32@2x'),('ic07','128'),('ic08','256'),('ic09','512'),('ic10','512@2x'),('ic11','16@2x'),('ic12','32@2x'),('ic13','128@2x'),('ic14','256@2x')]
chunks = []
for kind, name in slots:
    data = (root / f'icon_{name}.png').read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
pathlib.Path('Resources/Faceprint.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
