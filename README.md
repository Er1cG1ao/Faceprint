<p align="center">
  <img src="Branding/Faceprint.png" width="128" alt="Faceprint app icon">
</p>

# Faceprint

**Your face, fewer passwords to type.**

A native macOS menu bar app that recognizes your face and fills your saved Mac password into supported system prompts. Open the password field, look at the camera, and review the request. A Dynamic Island shows the recognition result along the way.

**English** · [简体中文](README.zh-CN.md)

[Download](https://github.com/Er1cG1ao/faceprint/releases/latest) · [User guide](Docs/TUTORIAL.md) · [Development](Docs/DEVELOPMENT.md) · [Report an issue](https://github.com/Er1cG1ao/faceprint/issues)

Built on [**Glance by Jonathan Zhou**](https://github.com/jonnyoo/glance), with direct reuse of its face recognition, guided enrollment, and Dynamic Island code and assets. Original attribution is preserved in the app and [third-party notices](THIRD_PARTY_NOTICES.md).

## What it does

- **Enroll from nine directions:** capture 18 face samples through Glance's guided ring and camera preview, using the same ArcFace model.
- **Fill supported prompts:** works with Privacy & Security and native Passwords AutoFill dialogs, including AutoFill for Dia.
- **See recognition at a glance:** choose Original or Minimal Dynamic Island animations, on displays with or without a notch.
- **Choose when to confirm:** review and submit yourself, or opt into automatic Return after a verified fill.
- **Keep saved data protected:** encrypt the password and face template locally, with a Secure Enclave protected session opened through macOS authentication.
- **Set up once:** first-launch permission requests, visible permission status, camera selection, and optional launch at login.

Built with Swift, SwiftUI, AppKit, AVFoundation, and Core ML. Face processing runs locally. The app interface currently uses English; documentation is available in English and Simplified Chinese.

### Current release: 1.0.0

The first stable release introduces Glance-inspired settings with six pages, translucent grouped controls, and a floating tab bar. Enrollment keeps its camera preview; Settings no longer has a live preview, test mode, camera-test button, or island-preview button. Filling requires an unlocked session, an enrolled face, and a saved password. See [release notes](RELEASE_NOTES.md).

## Install and start

Requires **Apple Silicon (M-series), macOS 15 or later**. Intel builds are not currently distributed.

1. Download `Faceprint-1.0.0-macos-arm64.zip` from **Assets** on the [latest release](https://github.com/Er1cG1ao/faceprint/releases/latest).
2. Quit the old version, extract the ZIP, and move `Faceprint.app` into **Applications** before granting permissions or enabling launch at login.
3. Open Faceprint and allow **Camera** and **Accessibility** access. Click **Unlock session** and complete the macOS authentication request.
4. Select your device in **Camera**, enroll from **Your Face**, and save your Mac login password in **Password**.
5. Leave automatic Return off in **Recognition**, then enable filling in **General**. Open a supported prompt, select **Use Password…** if needed, and focus the empty password field.
6. After recognition, review the request and filled field, then confirm or cancel it yourself.

Keep Faceprint running. Closing Settings leaves it in the menu bar; quitting stops recognition and locks the session. Launch at login opens the app with saved data locked. See the [guide](Docs/TUTORIAL.md) for sessions, automatic Return, photo checks, and troubleshooting.

Distributed builds use ad hoc signing and are **not Apple-notarized**.

## Scope and privacy

- Supports specific Apple system password dialogs. Faceprint fills the password fallback after you open it; it does not replace macOS Touch ID, unlock the lock screen, or provide Face ID hardware.
- Recognition uses an ordinary RGB camera. **Photos or replayed video can be accepted.** Optional Glance Light photo checks reject some obvious spoofs and can also misidentify real users; they do not provide reliable replay protection.
- Native Passwords AutoFill matching currently relies on English dialog wording. A verified fill checks input length; macOS decides whether the password is correct and whether the action succeeds.
- Automatic Return is **off by default**. Enabling it can confirm a privileged settings change.
- Camera images are processed in memory. Saved face embeddings and the password are encrypted on your Mac. Sessions lock on screen lock, sleep, user-session switch, quit, or 30 minutes without secret use. See [local data and privacy](Docs/TUTORIAL.md#local-data-and-privacy).
- InsightFace pretrained weights carry separate **non-commercial research terms**. The code's MIT license does not grant additional rights to the model. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Build from source

Install current Apple Command Line Tools on an Apple Silicon Mac and have Glance installed locally for its compiled model and animation assets.

```sh
git clone https://github.com/Er1cG1ao/faceprint.git
cd faceprint
bash setup-resources.sh
bash build.sh
bash test.sh
```

Output: `Faceprint.app`. Building does not install or publish it. Resource import, source layout, tests, and packaging are documented in [Development](Docs/DEVELOPMENT.md).

## Help and contribute

Open an [Issue](https://github.com/Er1cG1ao/faceprint/issues) with the Faceprint version, macOS version, camera model, reproduction steps, and expected versus actual behavior. Remove private information from logs and screenshots. **Never upload passwords, face templates, camera recordings, or the local vault.**

[English guide](Docs/TUTORIAL.md) · [中文教程](Docs/TUTORIAL.zh-CN.md) · [Development](Docs/DEVELOPMENT.md) · [Release notes](RELEASE_NOTES.md)

## License and origins

[MIT](LICENSE) for Faceprint code, with [Glance's original MIT notice](LICENSE-Glance.txt) preserved for reused components. Thanks to **Jonathan Zhou** for Glance and to **InsightFace's authors** for the face-recognition model. The Faceprint icon was created with AI image generation; its source artwork is in [`Branding/Faceprint.png`](Branding/Faceprint.png). See [third-party notices](THIRD_PARTY_NOTICES.md) for upstream revisions and model terms.
