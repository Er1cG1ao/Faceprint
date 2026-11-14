#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build-cache
swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build-cache" \
    Sources/UpdateCore.swift Tests/UpdateSelfTest.swift -o .build-cache/UpdateSelfTest
.build-cache/UpdateSelfTest "$@"
