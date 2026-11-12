# Faceprint user guide

[Home](../README.md) · **English** · [简体中文](TUTORIAL.zh-CN.md)

This guide describes the 1.2.1 development/test build; the published stable release may expose fewer features.

## Set up

Download the app ZIP from [Releases](https://github.com/Er1cG1ao/faceprint/releases), quit any older instance, extract it, and move Faceprint into Applications. The app requires Apple Silicon and macOS 15+. It is ad hoc signed and not Apple-notarized.

On first launch, Faceprint requests Camera access and prompts for Accessibility access. On the **Camera** page, check both statuses. Camera is used for local recognition; Accessibility is used to inspect supported system dialogs and type into their password fields. If access is blocked, use the permission buttons and allow Faceprint in System Settings. Return to Faceprint to refresh the status.

Click **Unlock to edit** and complete the macOS authentication request. Select your device on **Camera**. On **Your Face**, click **Enroll my face** and follow the nine-direction ring. Move gently and hold each position. The guide captures two samples per direction. Save your Mac login password on **Password** after enrollment. The camera preview appears only during enrollment.

## First password fill

1. Complete setup: unlock settings, enroll your face, and save your Mac login password.
2. In **Recognition**, leave **Press Return after filling** off for the first use.
3. In **General**, turn on **Enable face-assisted filling**.
4. Open a supported system password dialog. Select **Use Password…** if necessary, then focus the empty password field.
5. Look at the camera. Once the password is filled, review the dialog and confirm or cancel it yourself.

Filling always uses your saved password. There is no test-character mode or camera/island preview control in Settings.

By default, open each prompt's password-entry step yourself. With Scan Touch ID prompts enabled, Faceprint scans when a supported visible Touch ID card is discovered and selects its explicit Use Password control only after recognition. It attempts a given field once. To retry after a failure, use **Retry current prompt** in the menu bar, or hover over the failure island while it remains visible.

## Locked settings and everyday autofill

Settings start locked. Click **Unlock to edit** (or the lock icon) and complete macOS authentication before changing any option, enrolling a face, updating the password, deleting saved data, or changing launch at login. Each settings unlock requests authentication, even while autofill is already running.

After setup, enable filling and click **Lock settings**. Enabled autofill keeps running while all editable controls remain locked. Closing Settings also locks editing; the menu bar app continues to run. Settings automatically lock after 5 minutes without a settings change. Locking settings cancels an unfinished enrollment, but does not cancel a recognition/fill already in progress.

The encrypted data session is separate. Its key still requires macOS user-presence authentication after app launch, screen lock, sleep, user-session switch, or 30 minutes without secret use. Faceprint remembers the filling switch and can authenticate to resume enabled autofill at launch. After a data lock, the next supported prompt can request authentication; **Resume autofill** in the menu or General page retries it. Cancelling authentication pauses automatic retries until you explicitly retry. Resuming autofill leaves settings locked.

Choose **Open Faceprint…** from the menu to reopen Settings. **Quit Faceprint** stops recognition and clears the data-session key.

On **General**, unlock settings and turn on **Launch at login** to register macOS Login Items. Install the app in Applications first. If approval is needed, click **Open Login Items**. Turning the switch off unregisters it. Login launch follows the same protected-data authentication rule above.

## Recognition and confirmation settings

Unlock settings and disable filling before changing these options:

| Setting | Behavior |
| --- | --- |
| Dynamic Island: Original / Minimal | Selects the visual style under General. |
| Passive photo checks (Glance Light) | Optional checks for obvious screen glare or a device around the face. No required blink or head turn. Defaults off for new installations; the choice is remembered. |
| Scan Touch ID prompts | Off by default. Recognizes the face at a supported Touch ID card, selects Use Password, and fills only a verified empty field for that same request. |
| Press Return after filling | Defaults off. When enabled, rechecks the target and sends Return only after verifying a real-password fill. |

With automatic Return off, review the dialog and click **Modify Settings** or **OK** yourself. With it on, filling can also approve the current privileged request. Input-length verification does not establish that the password is correct; the system dialog decides that.

Photo checks can reject real users and cannot reliably stop replay attacks. Ordinary RGB face recognition can accept a photo or recorded video, especially with checks off.

## Face-first Touch ID flow

Unlock settings, turn filling off in General, and enable **Scan Touch ID prompts** in Recognition. Enable **Press Return after filling** as well if you want final submission, then turn filling back on and lock Settings.

| Touch ID scanning | Automatic Return | Result |
| --- | --- | --- |
| Off | Off | You open the password field; Faceprint recognizes and fills; you submit. |
| Off | On | You open the password field; Faceprint recognizes, fills and submits. |
| On | Off | Faceprint recognizes at the Touch ID card, selects Use Password and fills; you submit. |
| On | On | Faceprint recognizes at the Touch ID card, selects Use Password, fills and submits. |

The scan does not click anything until your face matches. The transition uses the explicit Accessibility button action, with no speculative Return. The resulting field must be empty and match the original request. A replacement signed Apple host is accepted only with a matching request heading (including known Settings unlock/modify aliases) and evidence that it is the same dialog (AX window identity, or matching card geometry after the original biometric stage disappears). System Settings has a specific native delegation to the Privacy & Security extension: after verified Use Password activation, an already focused empty field in that Apple-signed extension may continue the same Privacy request without cross-XPC window metadata, while the expected foreground is retained. A changed request, unavailable button, timeout or failed verification stops the flow. If a host change cannot be linked to the original card, or wording is not recognized, use the manual password-entry path and Retry current prompt. This version supports English Touch ID wording for the existing supported dialog types.

Visible supported Touch ID cards can also be discovered before they have keyboard focus. After a face match, Faceprint activates that card if necessary and invokes its verified Use Password control. Switching apps during that scan cancels it; multiple simultaneous cards are not chosen automatically.

After a face match the camera stops. Password fallback confirms the same empty, focused secure field again after about 40 ms, with a 3-second transition timeout and no fixed animation grace. Finder’s user-name field is not used for password input. Failed continuation does not immediately start a second scan; use **Retry current prompt** to retry.

## Supported dialogs

- Privacy & Security and matching System Settings extension account-password prompts (extension or native authentication-agent host).
- English native SecurityAgent/LocalAuthentication requester/action prompts and installer administrator forms.
- Finder’s English “wants to move … to the Trash” and “wants to make changes” authorization prompts (including Undo).
- Native Passwords AutoFill verification, including AutoFill for Dia. Matching currently depends on English dialog text and the current account.

The app verifies supported Apple processes and dialog context. Visible supported password fields can also start recognition before gaining keyboard focus; a face match is required before focus is requested. Arbitrary website/app account forms, Apple Account/keychain/disk passwords, lock-screen unlocking, passkeys, and Apple Pay approval are outside the saved-Mac-password flow. Custom or unrecognized wording can still require manual authentication.

The same ArcFace model and similarity thresholds are used with two distinct matching frames. Model warm-up and camera reuse reduce startup work. Where supported, the secure field receives one AXValue assignment; otherwise native keyboard delivery is retained. A quick length check remains before optional Return.

If a workflow stalls, click **Copy diagnostics** below the Settings status after that attempt, before triggering another. It copies elapsed phases and system-host metadata, without password, face or prompt/file-title data. See [Performance notes](PERFORMANCE.md).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No image during enrollment | Check Camera permission and the selected device on Camera. Settings has no live preview. |
| Enrollment stops | Use steady lighting, keep your face close enough, and turn gently. Restart enrollment after a timeout. Report any crash with its version and steps. |
| Nothing triggers | Check filling is enabled, a face/password are saved, Accessibility is allowed, and the supported field is empty and focused. Use Resume autofill if protected data needs authentication. |
| Dia works but another prompt does not | Check whether the prompt is supported and in English. Include the dialog type in a bug report with private details removed. |
| Failed attempt will not retry | Choose Retry current prompt or use the failure-island hover action. |
| Protected data is locked after sleep | Use Resume autofill or focus the next supported prompt to authenticate. Settings can stay locked; the filling preference is remembered. |
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
