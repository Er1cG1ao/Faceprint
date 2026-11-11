# Faceprint 1.1.1

- Recognize Privacy & Security’s “unlock system settings” Touch ID wording as well as “modify your system settings”.
- Discover visible supported Touch ID cards even when their controls are not focused. After a successful face match, activate and raise the verified card, focus its fallback control, and select Use Password. No blind Return or click coordinates are used.
- Abort if the user changes apps during a background-card scan, the request disappears, or several cards are ambiguous. Recheck the focused Apple-signed card before switching; preserve same-request empty-field checks before filling.
- Normalize the Icon Composer PNG into standard inset ICNS sizes with dimension-checked ICNS slots, removing the invalid 64px image in the 48px icp6 slot and full-bleed legacy artwork. About uses the original rounded branding image separately.

Build and regression tests cover the reported wording and prior request exclusions. Real Touch ID card discovery/focus and system icon rendering still require verification on the user’s Mac. Existing Scan Touch ID prompts and automatic Return options remain independent and unchanged.

# Faceprint 1.1.0

- Add opt-in Scan Touch ID prompts under Recognition (off by default, protected by the settings edit lock).
- Recognize the enrolled face before selecting Use Password on supported English Privacy & Security / native Passwords AutoFill Touch ID cards.
- Revalidate the signed Apple process and request before pressing the fallback button. Fill only the same process/request's verified empty secure field; no speculative Return is sent during transition.
- Combine with the independent existing automatic Return option for final submission after verified input.
- Preserve the manual password-entry path, settings lock, saved data and rounded icon.

Build, prompt-classification/fallback-context regression tests, existing self-tests, signature and ZIP checks passed. Live Touch ID-to-password transitions and real-password filling still need user verification. Different dialog hosts/wording may require the manual path. This does not replace Touch ID, enable lock-screen unlocking or add support for unrelated authentication dialogs.

Apple Silicon, macOS 15+. Ad-hoc signed and not Apple-notarized. Built on [Glance by Jonathan Zhou](https://github.com/jonnyoo/glance), MIT. InsightFace weights retain separate non-commercial research terms. [Third-party notices](THIRD_PARTY_NOTICES.md)

---

# Faceprint 1.0.1

- Separate the settings edit lock from protected autofill data. Settings start locked; enabled autofill continues when settings are locked or closed.
- Require fresh macOS authentication to edit all options, enroll a new face, update the password, remove saved data or change launch at login. Late authentication results cannot reopen settings after locking.
- Remember the filling and photo-check choices. Resume enabled autofill after launch through the existing hardware-protected data authentication. Add Resume autofill for cancelled or expired data sessions.
- Keep data-key clearing on screen lock, sleep, user-session switch, quit and 30-minute inactivity; do not prompt while the workstation is locked or asleep. Settings relock after 5 minutes without a settings change.
- Use the project owner's rounded Icon Composer export in the app icon and About page.

Existing saved data remains compatible. Opening protected data still requires macOS user-presence authentication after launch or a data-session lock; locking settings alone does not discard that key.

Validation includes default-locked state, stale-authentication rejection, edit-policy checks, autofill independence, existing self-tests, build/signature and ZIP checks. Live system authentication, screen-lock/wake transitions and real-password filling still require user verification.

Apple Silicon, macOS 15+. Ad-hoc signed and not Apple-notarized. Built on [Glance by Jonathan Zhou](https://github.com/jonnyoo/glance), MIT; InsightFace weights retain separate non-commercial research terms. [Third-party notices](THIRD_PARTY_NOTICES.md)

---

# Faceprint 1.0.0

First stable release.

- Redesign Settings around Glance's translucent groups, compact header and floating pill navigation: General, Your Face, Password, Camera, Recognition, and About.
- Remove the Settings camera preview, test mode, Test camera, and Preview Dynamic Island controls. The nine-direction enrollment preview remains available during enrollment.
- Require an unlocked session, an enrolled face and a saved password before enabling filling. Recognition now always fills the saved password.
- Retain Original and Minimal island styles, optional automatic Return, local encrypted storage, launch at login and first-launch permission requests.
- Preserve existing face templates, passwords and preferences.

Apple Silicon, macOS 15+. Ad-hoc signed; not Apple-notarized. Ordinary webcam recognition can accept photos or replayed video. Native Passwords AutoFill matching currently relies on English dialog text.

Validation: build, automated prerequisite/Return policy tests, enrollment/template/Unicode/context self-tests, signature and ZIP checks. Live enrollment, settings navigation and post-authentication focus behavior have not been reverified for this release.

Built on [Glance by Jonathan Zhou](https://github.com/jonnyoo/glance), with its original MIT notice preserved. InsightFace pretrained weights retain separate non-commercial research terms. [Third-party notices](https://github.com/Er1cG1ao/faceprint/blob/main/THIRD_PARTY_NOTICES.md)

---

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
