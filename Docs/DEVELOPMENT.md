# Faceprint development

[Home](../README.md) · [User guide](TUTORIAL.md) · [中文教程](TUTORIAL.zh-CN.md)

## Build

Use an Apple Silicon Mac with current Apple Command Line Tools and a macOS SDK supporting the project's APIs. The deployment target is macOS 15. The build uses Swift 5 language mode and produces an arm64 app. Python 3 is used to package the icon.

Install Glance locally, then run:

```sh
git clone https://github.com/Er1cG1ao/faceprint.git
cd faceprint
bash setup-resources.sh
bash build.sh
bash test.sh
```

`setup-resources.sh` imports the compiled ArcFace model and scan media from `/Applications/Glance.app`. Pass another Glance app path as its first argument if needed. These imported runtime resources are excluded from Git. Check their [separate license terms](../THIRD_PARTY_NOTICES.md) before using or redistributing them.

`build.sh` compiles Swift sources, generates `Resources/Faceprint.icns` from `Branding/Faceprint.png`, copies notices and runtime assets, and ad hoc signs `Faceprint.app`. It does not install, register a login item, or publish the app.

## Source map

| Location | Responsibility |
| --- | --- |
| `Sources/App.swift` | Menu bar, independent settings/data-session state, enrollment and filling coordination. |
| `Sources/SettingsView.swift` | Six-page settings, translucent groups and floating tab navigation. |
| `Sources/Camera.swift` | Serialized capture-session operations and the latest in-memory frame. |
| `Sources/GuidedEnrollment.swift` | Nine-direction, 18-sample capture flow. |
| `Sources/Recognition.swift` | ArcFace recognition and encrypted face-template storage. |
| `Sources/PromptPolicy.swift`, `Sources/PromptTarget.swift` | Supported Apple dialog context, target revalidation, text input and Return. |
| `Sources/InputActionPolicy.swift` | Settings authorization tickets, filling prerequisites and auto-Return policy. |
| `Sources/SecureCredentialManager.swift` | Secure Enclave session key and encrypted vault. |
| `Sources/SystemSetup.swift` | macOS permissions and Login Items registration/status. |
| `Sources/Upstream/` | Glance code and adaptations, including enrollment and Dynamic Island views. |
| `Branding/` | AI-generated Faceprint artwork and icon packaging script. |

Upstream baseline: Glance revision `b97f521397ec1197ba17768ba797cae1e628848d`. Preserve the original MIT notice when changing reused files. Camera previews render the existing captured frames rather than attaching `AVCaptureVideoPreviewLayer` instances during session startup; this avoids the concurrent session mutation seen in the enrollment crash.

## Validation

`bash test.sh` runs self-tests for automatic Return policy, nine-pose order and capture bands, template compatibility, Unicode chunking, and supported AutoFill context. `bash build.sh` verifies compilation. These tests do not authenticate a live system dialog or establish face-recognition security.

Before a release, manually check camera start/stop, enrollment start/cancel/retry, session authentication focus, permission states, and Login Items behavior from an installed app. Keep automatic Return off for the first live fill and review the field before confirming. Verify optional Return only against a request you intend to approve. Record untested behavior in the release notes.

## Package a release

Stage only the built app, verify its signature, then archive it:

```sh
stage=$(mktemp -d /tmp/faceprint-package.XXXXXX)
ditto --norsrc --noextattr --noqtn Faceprint.app "$stage/Faceprint.app"
codesign --verify --strict --verbose=2 "$stage/Faceprint.app"
ditto -c -k --norsrc --noextattr --noqtn --keepParent \
  "$stage/Faceprint.app" Faceprint-macos-arm64.zip
unzip -t Faceprint-macos-arm64.zip
shasum -a 256 Faceprint-macos-arm64.zip
```

Publish a release with app version, architecture, macOS requirement, signing status, known limitations, and upstream/model notices. Compare the uploaded asset's SHA-256 with the local archive. Do not package build caches, private logs, face templates, passwords, or vault files.

## Data compatibility

The encrypted vault retains the prototype path `~/Library/Application Support/GlanceFill/vault-v1.json` and derivation context `local.giao.glancefill.vault.v1`. Preferences use `io.github.er1cg1ao.faceprint`, with migration of the old camera selection. Changing the vault path, key context, or encrypted data format requires a deliberate migration.

The Secure Enclave protects the private key used to derive a session key; user presence gates opening the session. The app holds the derived key while the protected data session is prepared. The separate settings lock gates mutations and is checked in controller setters as well as UI controls. Settings authentication uses a fresh LAContext even when the data key already exists. Review both hardware protection and in-process handling when changing this flow.

## Contributions

Keep changes focused and describe the trigger, resulting behavior, validation, and remaining limits. File ordinary bugs through [Issues](https://github.com/Er1cG1ao/faceprint/issues), without private data. Do not make biometric security claims from input-filling tests or equate webcam recognition with Face ID.

[MIT license](../LICENSE) · [Glance license](../LICENSE-Glance.txt) · [Third-party notices](../THIRD_PARTY_NOTICES.md)
