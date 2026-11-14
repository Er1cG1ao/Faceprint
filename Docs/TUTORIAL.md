# Faceprint user guide

[Home](../README.md) · **English** · [简体中文](TUTORIAL.zh-CN.md)

This guide describes Faceprint 1.6.1.

## Set up

Download the app ZIP from [Releases](https://github.com/Er1cG1ao/faceprint/releases), quit any older instance, extract it, and move Faceprint into Applications. The app requires Apple Silicon and macOS 15+. Version 1.6.1 is Apple Development signed and not Apple-notarized.

On first launch, Faceprint requests Camera access and prompts for Accessibility access. On **General**, check both statuses under **Permissions** at the top (the block hides once both are granted). Camera is used for local recognition; Accessibility is used to inspect supported system dialogs and type into their password fields. If access is blocked, use the permission buttons and allow Faceprint in System Settings. Return to Faceprint to refresh the status.

Click **Unlock session** and complete the macOS authentication request. Select your device on **Camera**. On **Your Face**, click **Enroll my face** and follow the nine-direction ring. Move gently and hold each position. The guide captures two samples per direction. After capture, enter or edit the suggested name in Name this face, then choose Save. Back repeats capture; closing Settings cancels without saving a new identity. Recapture preserves its existing name. Your Face shows identity cards with names, enable switches, sample-quality ticks, Recapture and Delete. Use + to add another named appearance or face. Only enabled identities participate in recognition; every enabled identity authorizes the same saved Mac password. Existing single-face data loads as an identity, with quality marked not recorded until recaptured. Save your Mac login password on **Password** after enrollment. The camera preview appears only during enrollment.

## First password fill

1. Complete setup: unlock settings, enroll your face, and save your Mac login password.
2. In **General**, leave **Press Return after filling** off for the first use.
3. In **General**, turn on **Enable face-assisted filling**.
4. Open a supported system password dialog. Select **Use Password…** if necessary, then focus the empty password field.
5. Look at the camera. Once the password is filled, review the dialog and confirm or cancel it yourself.

Filling always uses your saved password. There is no test-character mode or camera/island preview control in Settings.

By default, open each prompt's password-entry step yourself. With Scan Touch ID prompts enabled, Faceprint scans when a supported visible Touch ID card is discovered and selects its explicit Use Password control only after recognition. It attempts a given field once. To retry after a failure, hover over the failure island while it remains visible (if enabled), or dismiss the dialog and reopen it after a short pause.

## Locked settings and everyday autofill

The settings session starts locked, showing **Session locked** until authenticated. Click **Unlock session** (or the Session capsule) and complete macOS authentication before changing any option, enrolling a face, updating the password, deleting saved data, or changing launch at login. Each settings unlock requests authentication, even while autofill is already running.

After setup, enable filling and click **Lock session**. Enabled autofill keeps running while all editable controls remain locked. Opening Settings shows Faceprint in the Dock and Cmd-Tab. Closing Settings hides those entries and locks the settings session; the menu bar app and enabled autofill continue to run. Settings automatically lock after 5 minutes without a settings change. Unlocking is sufficient for editing: you do not need to turn autofill off. Enrollment temporarily takes over the camera, then automatic filling resumes with its preference unchanged. Updating the password interrupts an active automatic fill; deleting saved data stops filling after confirmation. Locking settings cancels an unfinished enrollment, but does not cancel a recognition/fill already in progress.

The encrypted data session is separate. It has no idle-time expiry and no Resume autofill authentication. V2 data is encrypted with a device-only Secure Enclave key available while macOS is unlocked, without per-use user-presence enforcement. Faceprint clears cached data and stops recognition at sleep, screen lock, user switch and quit; when the Mac is available again, enabled autofill reopens its store automatically without another fingerprint. Editing still requires Unlock session. Existing v1 data needs one explicit Settings unlock to migrate; the encrypted original is backed up before the v2 replacement. No migration failure deletes saved data.

Choose **Settings…** from the menu to reopen Settings. If the menu bar icon is hidden, launch the running Faceprint app again (for example from Applications or Spotlight). This reopens Settings; it does not quit the background app. **Quit Faceprint** stops recognition and clears the data-session key.

On **General**, unlock settings and turn on **Launch at login** to register macOS Login Items. Install the app in Applications first. If approval is needed, click **Open Login Items**. Turning the switch off unregisters it. Login launch follows the same protected-data authentication rule above.

## Recognition and confirmation settings

Unlock the session to change these options in **General**. Autofill can remain enabled. Ordinary recognition/camera/style options apply to the next attempt; changing saved data or starting enrollment coordinates the active task automatically.

| Setting | Behavior |
| --- | --- |
| Animation: Show animation / Minimal / Original | Controls feedback visibility and style under General. |
| Passive photo checks (Glance Light) | Optional checks for obvious screen glare or a device around the face. No required blink or head turn. Defaults off for new installations; the choice is remembered. |
| Scan Touch ID prompts | Off by default. Recognizes the face at a supported Touch ID card, selects Use Password, and fills only a verified empty field for that same request. |
| Press Return after filling | Defaults off. When enabled, rechecks the target and sends Return only after verifying a real-password fill. |

With automatic Return off, review the dialog and click **Modify Settings** or **OK** yourself. With it on, filling can also approve the current privileged request. Input-length verification does not establish that the password is correct; the system dialog decides that.

Photo checks can reject real users and cannot reliably stop replay attacks. Ordinary RGB face recognition can accept a photo or recorded video, especially with checks off.

## Face-first Touch ID flow

Unlock the session and enable **Scan Touch ID prompts** under **General → Behavior**. Enable **Press Return after filling** as well if you want final submission, then enable filling if it is off and lock Settings.

| Touch ID scanning | Automatic Return | Result |
| --- | --- | --- |
| Off | Off | You open the password field; Faceprint recognizes and fills; you submit. |
| Off | On | You open the password field; Faceprint recognizes, fills and submits. |
| On | Off | Faceprint recognizes at the Touch ID card, selects Use Password and fills; you submit. |
| On | On | Faceprint recognizes at the Touch ID card, selects Use Password, fills and submits. |

The scan does not click anything until your face matches. The transition uses the explicit Accessibility button action, with no speculative Return. The resulting field must be empty and match the original request. A replacement signed Apple host is accepted only with a matching request heading (including known Settings unlock/modify aliases) and evidence that it is the same dialog (AX window identity, or matching card geometry after the original biometric stage disappears). System Settings has a specific native delegation to the Privacy & Security extension: after verified Use Password activation, an already focused empty field in that Apple-signed extension may continue the same Privacy request without cross-XPC window metadata, while the expected foreground is retained. A changed request, unavailable button, timeout or failed verification stops the flow. If a host change cannot be linked to the original card, or wording is not recognized, dismiss and reopen the request, then use its manual password-entry path. This version supports English Touch ID wording for the existing supported dialog types.

Visible supported Touch ID cards can also be discovered before they have keyboard focus. After a face match, Faceprint activates that card if necessary and invokes its verified Use Password control. Switching apps during that scan cancels it; multiple simultaneous cards are not chosen automatically.

After a face match the camera stops. Password fallback confirms the same empty, focused secure field again after about 40 ms, with a 3-second transition timeout and no fixed animation grace. Finder’s user-name field is not used for password input. Failed continuation does not immediately start a second scan; hover the held failure island (if enabled), or dismiss and reopen the prompt to retry.

## Supported dialogs

- Privacy & Security and matching System Settings extension account-password prompts (extension or native authentication-agent host).
- English native SecurityAgent/LocalAuthentication requester/action prompts and installer administrator forms.
- Finder’s English “wants to move … to the Trash” and “wants to make changes” authorization prompts (including Undo).
- Native Passwords AutoFill verification, including AutoFill for Dia. Matching currently depends on English dialog text and the current account.

The app verifies supported Apple processes and dialog context. Visible supported password fields can also start recognition before gaining keyboard focus; a face match is required before focus is requested. Arbitrary website/app account forms, Apple Account/keychain/disk passwords, lock-screen unlocking, passkeys, and Apple Pay approval are outside the saved-Mac-password flow. Custom or unrecognized wording can still require manual authentication.

The same ArcFace model and similarity thresholds are used with two distinct matching frames. Model warm-up and camera reuse reduce startup work. Where supported, the secure field receives one AXValue assignment; otherwise native keyboard delivery is retained. A quick length check remains before optional Return.

The menu bar menu is limited to Settings… and Quit Faceprint. Troubleshooting status remains in the menu icon’s tooltip when shown. Copy diagnostics and other troubleshooting shortcuts are no longer in the menu.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No image during enrollment | Check permission under General → Permissions and the selected device on Camera. Settings has no live preview. |
| Enrollment stops | Use steady lighting, keep your face close enough, and turn gently. Restart enrollment after a timeout. Report any crash with its version and steps. |
| Nothing triggers | Check filling is enabled, a face/password are saved, Accessibility is allowed, and the supported field is empty and focused. Unlock the settings session if protected data needs authentication. |
| Dia works but another prompt does not | Check whether the prompt is supported and in English. Include the dialog type in a bug report with private details removed. |
| Failed attempt will not retry | Use the failure-island hover action (if enabled), or dismiss and reopen the prompt. |
| Protected data is locked after sleep | Unlock the settings session or focus the next supported prompt to authenticate. Settings can stay locked; the filling preference is remembered. |
| Launch at login cannot be enabled | Move the app to Applications and check Login Items approval in System Settings. |
| Password filled but request rejected | Check the saved Mac login password. The app checks the fill, while macOS checks the credential. |

## Local data and privacy

Camera frames are processed locally in memory. Face embeddings and the saved password are encrypted separately with AES-GCM. A user-presence-protected Secure Enclave P-256 key derives the session key through ECDH and HKDF-SHA256.

The app retains the prototype's vault path for compatibility:

```text
~/Library/Application Support/GlanceFill/vault-v1.json
```

Preferences use the `io.github.er1cg1ao.faceprint` domain. Hardware-key material is device-bound; copying the vault does not provide a supported migration to another Mac. The opaque key representation can let another process initiate an authentication request, but deriving the session key still requires the hardware-enforced user-presence check.

Use **Remove saved data…** to remove the saved face and password through the app's confirmation dialog. To stop launch at login, turn that setting off separately before removing the app.

For reports, include app/macOS versions, camera model, steps, and the visible status message. Never attach passwords, the vault, face templates, or camera recordings.

[Development](DEVELOPMENT.md) · [Third-party notices](../THIRD_PARTY_NOTICES.md)

## Behavior and animation

In General → Behavior, Retry on notch hover controls hover activation after a failed scan while the failed request remains present; the collapsed notch/pill stays hoverable. Auto retry once after failure is off by default: it retries recognition once for the same rediscovered, Apple-verified request after the failure feedback ends. Each retry uses fresh frames and a fresh face match. Disabling the option, disabling filling, editing saved faces/password, sleep or locking the screen cancels a pending retry. After a handoff/input failure, a retry is allowed only for a newly verified matching empty field; a nonempty or unverifiable field blocks it. Each retry performs a new face match. A manual hover retry resets the retry budget.

General → Animation has Show animation and Minimal/Original style tiles. Hiding animation does not disable recognition, filling or optional Return. Selecting a style previews it when Faceprint is idle; it does not interrupt an active scan or enrollment. Missing permissions appear at the top of General and disappear after both grants are refreshed.

## Updates and macOS permissions

In About, Check contacts the public GitHub latest stable release. Automatically check for updates checks once daily on launch; it does not download or install without confirmation. Newer compatible releases show Install and Restart. Keep Faceprint at a writable /Applications or ~/Applications location. The updater checks the archive hash, paths, app metadata, architecture and signatures, then replaces the app at the same path after quitting. The previous app remains beside it as a hidden .Faceprint-backup-….app recovery copy. Saved faces, encrypted password and preferences remain in their existing locations. After migration to v2, restarting automatically reopens encrypted data without a Resume prompt.

The 1.6.1 release is signed with a fixed Apple Development identity. The first transition from older ad hoc builds may require Camera/Accessibility authorization once again. Future updates must satisfy the existing signing identity; using the same app name or installation path alone is insufficient. The updater never edits TCC, resets permissions, weakens code requirements or guarantees OS permission retention. The package is development-signed and is not Apple-notarized.

Settings hides repetitive session/recognition footers. About keeps update progress and license links.

General → Show in menu bar is directly below Launch at login. Turning it off hides only the status icon, leaving filling running. Open the app again through Applications or Spotlight to restore Settings. Changes require Unlock session. The application menu also provides Settings… (Command-comma) while the settings window is open.


## 1.6.0 recovery and retry

If upgrading a v1 vault, unlock the Settings Session once. Faceprint decrypts both old payloads, reseals them under a device-only noninteractive hardware key, then writes v2 atomically. A 0600 encrypted backup is kept at `~/Library/Application Support/GlanceFill/vault-v1-before-automatic.json`; Remove saved data removes it too. Do not replace your vault with this backup while any Faceprint instance is running. V2 is not readable by earlier versions.

Command-W closes Settings and locks editing, leaving enabled autofill running. The island no longer displays a Filling label. A failed scan leaves a resting hover target until the request is dismissed; hover manually restarts after fresh request verification, and Auto retry once schedules one fresh scan automatically. Recreated AX fields and linked native password stages are supported; a changed request or a nonempty password field stops retries.
