# Faceprint 0.1.1-beta.2

- Fix the enrollment startup crash: camera previews now share captured frames instead of attaching preview layers while the capture session starts.
- Restore the visible settings window after session authentication.
- Explain what Unlock session authorizes and when sessions lock.
- Add Faceprint's new face-and-fingerprint app icon.
- Add opt-in launch at login using macOS Login Items, including approval and error status.
- Request Camera and Accessibility access on first launch; show permission status and recovery actions in settings.

Apple Silicon, macOS 15+. Ad-hoc signed and not notarized. Login launch keeps the vault locked. Existing encrypted data remains compatible.

Built on [Glance by Jonathan Zhou](https://github.com/jonnyoo/glance), with its original MIT notice preserved. InsightFace pretrained weights retain their separate non-commercial research terms. [Third-party notices](https://github.com/Er1cG1ao/faceprint/blob/main/THIRD_PARTY_NOTICES.md)

---

# Faceprint 0.1.0-beta.1

First Faceprint beta, developed from the Glance Fill prototype.

- Renamed the app and menus to Faceprint.
- Added Original and Minimal Dynamic Island settings.
- Added optional automatic Return after a verified password fill. The setting defaults off and is ignored in test mode.
- Includes Glance's nine-direction capture UI and the same ArcFace model.
- Retains verified filling for Privacy & Security and native Passwords AutoFill.

Faceprint is built on Glance by Jonathan Zhou. Glance's original MIT license and detailed third-party notices are included in the app and repository. The pretrained model is subject to InsightFace's separate non-commercial research terms.

The app ZIP is an Apple Silicon, ad-hoc-signed experimental beta. Allow Camera and Accessibility access during setup. Start with test mode, then enable real filling after checking the single-character test.

[Glance](https://github.com/jonnyoo/glance) · [Third-party notices](https://github.com/Er1cG1ao/faceprint/blob/main/THIRD_PARTY_NOTICES.md)
