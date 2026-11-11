#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
iconroot=$(mktemp -d /tmp/faceprint-icon.XXXXXX)
trap 'rm -rf "$iconroot"' EXIT
mkdir -p "$iconroot/Faceprint.iconset" .build-cache
# Icon Composer PNG exports fill their canvas. Legacy macOS ICNS artwork
# needs the standard inset; a full-bleed rounded export is normalized again
# by Icon Services, producing a second gray tile in some system surfaces.
swift -module-cache-path "$PWD/.build-cache" Branding/render-icon.swift \
    Branding/Faceprint.png "$iconroot/Faceprint.iconset"
# Keep slots dimension-correct. In particular, icp6 is a 48px slot, not
# the 64px Retina representation of a 32px icon (that belongs in ic12).
python3 - "$iconroot/Faceprint.iconset" <<'PYICON'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
slots = [('icp4',16,1), ('icp5',32,1), ('ic07',128,1), ('ic08',256,1),
         ('ic09',512,1), ('ic10',512,2), ('ic11',16,2), ('ic12',32,2),
         ('ic13',128,2), ('ic14',256,2)]
chunks = []
for kind, size, scale in slots:
    suffix = '@2x' if scale == 2 else ''
    data = (root / f'icon_{size}x{size}{suffix}.png').read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (size * scale, size * scale)
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
pathlib.Path('Resources/Faceprint.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PYICON
