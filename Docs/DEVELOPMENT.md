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
| `Sources/SettingsView.swift` | Five-page settings, General recognition/permission groups and floating tab navigation. |
| `Sources/Camera.swift` | Serialized capture-session operations and the latest in-memory frame. |
| `Sources/GuidedEnrollment.swift` | Nine-direction, 18-sample capture flow. |
| `Sources/Recognition.swift` | ArcFace recognition and encrypted face-template storage. |
| `Sources/PromptPolicy.swift`, `Sources/PromptTarget.swift` | Supported password/Touch ID context, same-request fallback, target revalidation, text input and Return. |
| `Sources/InputActionPolicy.swift` | Settings authorization tickets, filling prerequisites and auto-Return policy. |
| `Sources/SecureCredentialManager.swift` | Secure Enclave session key and encrypted vault. |
| `Sources/SystemSetup.swift` | macOS permissions and Login Items registration/status. |
| `Sources/Upstream/` | Glance code and adaptations, including enrollment and Dynamic Island views. |
| `Branding/` | AI-generated Faceprint artwork and icon packaging script. |

Upstream baseline: Glance revision `b97f521397ec1197ba17768ba797cae1e628848d`. Preserve the original MIT notice when changing reused files. Camera previews render the existing captured frames rather than attaching `AVCaptureVideoPreviewLayer` instances during session startup; this avoids the concurrent session mutation seen in the enrollment crash.

## Validation

`bash test.sh` runs self-tests for automatic Return policy, nine-pose order and capture bands, template compatibility, Unicode chunking, and supported AutoFill context. `bash build.sh` verifies compilation. `swift Tests/ModelTiming.swift Resources/ArcFace.mlmodelc` measures the isolated Core ML component on synthetic input; see [Performance notes](PERFORMANCE.md). These tests do not authenticate a live system dialog or establish face-recognition security.

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

The Secure Enclave protects the private key used to derive a session key; user presence gates opening the session. The app holds the derived key while the protected data session is prepared. The separate settings lock gates mutations and is checked in controller setters as well as UI controls. Editing is independent of the enabled autofill preference and automatic recognition busy state; protected-data edits coordinate cancellation and enrollment explicitly. Ordinary option snapshots take effect on the next attempt. Automatic Return checks both the captured and current preference before dispatch. Settings authentication uses a fresh LAContext even when the data key already exists. Review both hardware protection and in-process handling when changing this flow.

## Contributions

Keep changes focused and describe the trigger, resulting behavior, validation, and remaining limits. File ordinary bugs through [Issues](https://github.com/Er1cG1ao/faceprint/issues), without private data. Do not make biometric security claims from input-filling tests or equate webcam recognition with Face ID.

[MIT license](../LICENSE) · [Glance license](../LICENSE-Glance.txt) · [Third-party notices](../THIRD_PARTY_NOTICES.md)


## Signed updates (1.5.0 development)

Build with `FACEPRINT_SIGN_IDENTITY` set to the exact codesigning identity name or SHA-1 available in your keychain. The default `-` remains ad hoc for local builds; no private key or signing certificate is checked into the repository. The helper is signed with its own identifier before sealing the main app. Developer ID distribution additionally needs the normal Apple notarization/stapling workflow, which this local build does not perform. Use one compatible signing identity across versions; changing to a Developer ID identity from an ad hoc build is a one-time permission migration, not a way to carry the old TCC record forward. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Publish a stable `vX.Y.Z` GitHub Release with `Faceprint-X.Y.Z-macos-arm64.zip`; GitHub's asset metadata must include `digest: sha256:…`. `/releases/latest` is the only update feed. No arbitrary release-note URLs, scripts or appcasts are executed. Ad hoc development updates trust the repo's HTTPS asset metadata plus ZIP digest and validate the app seal/identifier. Signed installations additionally require compatible designated requirements both ways and refuse an unsigned or differently signed replacement.

Run `bash test-update.sh ZIP NEW_APP [OLD_APP]` to check update policy, real archive paths, tampering and signature validity. With an older compatible app supplied, it installs copies inside a temporary Applications directory and verifies the recovery copy. It never invokes the production installer against the real Applications directory. `bash test.sh` runs recognition/prompt/authorization regressions.

The helper copies the verified app onto the destination volume and uses `renameatx_np(RENAME_SWAP)` for atomic replacement. The original app stays as `.Faceprint-backup-UUID.app`; its path is reported on next launch. Failed swap leaves the old app in place. A failed `/usr/bin/open` relaunch command swaps back. A successful launch request does not prove the new app cannot crash later, so the recovery copy is retained. Installer receipts and temporary downloads live under the per-user Faceprint Updates cache. No administrator helper, TCC database access or permission resets are used.


## 1.6.0 test vault/runtime changes

Vault v2 uses a Secure Enclave P256 ECDH key with `.privateKeyUsage` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, without `.userPresence`. Automatic opens set `LAContext.interactionNotAllowed = true`. V1 import accepts an already evaluated Settings context, authenticates both AES-GCM payloads with their original purpose strings, creates the v2 key, reseals both and atomically writes only after all steps succeed. Keep an encrypted v1 recovery copy. A store revision prevents late background opens committing after lock/removal. This changes the at-rest authorization model intentionally; it is not Face ID hardware matching.

Retry anchors are captured before recognition, compare newly discovered signed/empty candidates by context and card identity/heading/geometry (plus the fixed Settings delegate), and never reuse a face match. Input-stage failures can retry only if the target is freshly confirmed empty. Retry budget and scan suppression are independent: at most one automatic retry; hover explicitly resets budget. An armed collapsed failure overlay preserves the hover entry after the short result animation. Live hardware/UI verification remains required; synthetic crypto and policy tests do not prove platform authorization or cursor delivery.


## Local Apple signing setup

Install Xcode and sign in yourself under Settings → Accounts. In Manage Certificates, create Apple Development for your Personal Team (or select Developer ID Application if your paid team provides it). Authentication and keychain prompts stay in Apple's UI; do not send passwords, verification codes, or private keys to the assistant. The identity must have its private key in this Mac's keychain.

Run `python3 Tools/configure-signing.py` to select the existing identity. If several exist, use `--identity SHA1` to choose explicitly. The ignored `.signing.local.json` pins that certificate; `build.sh` automatically uses it and refuses to silently fall back to ad hoc if it expires or disappears. `--require` records that stable signing is required while initial account setup is pending. Other checkouts without this local requirement may still build ad hoc; `FACEPRINT_ALLOW_ADHOC=1` explicitly permits local debug fallback.

Signed builds verify Apple's chain and store the app's default designated requirement in the ignored `.signing.requirement`. Subsequent builds require identical requirements. This does not weaken or override macOS requirements. The updater separately checks mutual compatibility between the installed and incoming signed apps. Keep the same bundle ID, certificate identity and installation path; do not delete/recreate signing assets casually. Renewal or switching from development to Developer ID requires reviewing compatibility against the installed app. Ad hoc-to-certificate migration may still need one final Camera/Accessibility authorization.

Only certificate metadata and public requirement data are stored in the checkout. The private signing key stays in the macOS keychain and is never exported, committed, or uploaded by these tools. Signing does not by itself notarize the application or guarantee every OS permission will persist.


## Sign on the Mac that holds the private key

When the developer certificate was created on another Mac, use that Mac locally instead of exporting its private key to chat. Clone this repository there and run `python3 Tools/sign-release-on-mac.py`. It selects the existing Apple identity, downloads a verified published arm64 archive, validates the GitHub SHA-256 and ZIP, increments the version/build, then signs the embedded installer and app. It signs a separate next-version probe and checks mutual requirements with the real package before making the output ZIP. It does not install, upload, export keys, alter trust or request account credentials. The default source is the latest stable Release and the output is its next patch version; `--source-version` and `--version` can pin explicit values.

The signed ZIP and `signing-report.json` are written to a unique Downloads folder on the signing Mac. Keep `.signing.local.json` and `.signing.requirement` in that checkout for future signing. Send only the signed ZIP/report for publication, never the certificate's private key or password. A change from the existing ad hoc installation still may need a one-time permission grant. After adopting a real signing identity, all subsequent release artifacts must use compatible signing; do not publish ad hoc updates for those installations. This workflow proves signature identity compatibility, not a live TCC permission migration, and does not notarize the app.


The local signing downloader uses `/usr/bin/curl` with normal TLS verification, HTTPS-only URLs and per-redirect GitHub host checks. This avoids Python.org installations whose separate CA bundle is not configured; it never uses `--insecure`, an unverified SSL context, or global trust overrides. Download limits, GitHub SHA-256 and archive/signature checks remain mandatory. If a certificate/private-key pair appears under matching identities but not valid identities, diagnose its trust chain; Apple Development normally uses the Apple WWDR G3 intermediate. Import the genuine Apple intermediate under normal trust rather than changing the leaf to Always Trust.


## Published signing identity (1.6.1)

SigningIdentity.json records only public identity metadata: Team ID, the reviewed leaf certificate fingerprint and the SHA-256 of the default designated requirement. SigningIdentityCheck enforces the Team and requirement hash before creating/updating a local baseline. Certificate renewal can be compatible if requirements stay unchanged; changing requirement type, team or account identity requires explicit review rather than silently updating the policy. Private keys stay on the signing Mac; the build Mac cannot sign merely by receiving a signed application. Public release artifacts after 1.6.1 must not regress to ad hoc signing.
