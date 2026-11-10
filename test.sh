#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build-cache
swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build-cache" \
    Tests/FaceprintSelfTest.swift Sources/InputActionPolicy.swift \
    Sources/EnrollmentPoseMatcher.swift Sources/KeyboardText.swift Sources/PromptPolicy.swift \
    Sources/Recognition.swift Sources/SecureCredentialManager.swift \
    Sources/Upstream/FaceAligner.swift Sources/Upstream/FaceDetector.swift \
    Sources/Upstream/FaceEmbedder.swift Sources/Upstream/ArcFaceEmbedder.swift \
    Sources/Upstream/Liveness/LandmarkGeometry.swift Sources/Upstream/Onboarding/EnrollmentPose.swift \
    -o .build-cache/FaceprintSelfTest
.build-cache/FaceprintSelfTest
