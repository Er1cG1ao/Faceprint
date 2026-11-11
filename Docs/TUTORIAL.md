# Faceprint user guide

[Home](../README.md) · **English** · [简体中文](TUTORIAL.zh-CN.md)

## Set up

Download the app ZIP from [Releases](https://github.com/Er1cG1ao/faceprint/releases), quit any older instance, extract it, and move Faceprint into Applications. The distributed beta requires Apple Silicon and macOS 15+. It is ad hoc signed and not Apple-notarized.

On first launch, Faceprint requests Camera access and prompts for Accessibility access. Under **Startup & Permissions**, check both statuses. Camera is used for local recognition; Accessibility is used to inspect supported system dialogs and type into their password fields. If access is blocked, use the permission buttons and allow Faceprint in System Settings. Return to Faceprint to refresh the status.

Click **Unlock session** and complete the macOS authentication request. Select your camera and use **Test camera** to check it; **Stop camera** ends the preview. Click **Enroll my face** and follow the nine-direction ring. Move gently and hold each position. The guide captures two samples per direction. Save your Mac login password in the app after enrollment.

## Try a single character first

1. Leave **Test mode — fill a single x after recognizing me** on.
2. Enable **face-assisted filling**.
3. Open a supported system password dialog. Select **Use Password…** if necessary, then focus the empty password field.
4. Look at the camera. A successful recognition fills one `x`; verify one masked dot, then click Cancel.
5. Disable filling, turn Test mode off, then enable filling again to use the saved password.

Faceprint leaves each prompt's password-entry step to you. It attempts a given field once. To retry after a failure, use **Retry current prompt** in the menu bar, or hover over the failure island while it remains visible.

## Sessions and everyday use

**Unlock session** authorizes access to the encrypted face template and saved password through a macOS user-presence check. It is needed after opening the app and after a session locks. Individual fills can then use that unlocked session without repeating this setup step.

The session locks on screen lock, sleep, user-session switch, quit, or 30 minutes without secret use. **Lock session** locks it immediately and disables filling. Unlock it and enable filling again to continue.

Closing Settings keeps the menu bar app running. Choose **Open Faceprint…** from its menu to return. **Quit Faceprint** stops the app and locks its data.

Under **Startup & Permissions**, turn on **Launch Faceprint at login** to register it with macOS Login Items. Install it in Applications first. If approval is needed, click **Open Login Items**. Turn the switch off to unregister it. Launching at login does not unlock saved data or enable filling automatically.

## Recognition and confirmation settings

Change these settings with filling disabled:

| Setting | Behavior |
| --- | --- |
| Dynamic Island: Original / Minimal | Selects the visual style. Use Preview Dynamic Island to see it. |
| Test mode | Types only `x`; never presses Return. Enabled on each app launch. |
| Passive photo checks (Glance Light) | Optional checks for obvious screen glare or a device around the face. No required blink or head turn. Defaults off on launch. |
| Press Return automatically after filling | Defaults off. When enabled, rechecks the target and sends Return only after verifying a real-password fill. |

With automatic Return off, review the dialog and click **Modify Settings** or **OK** yourself. With it on, filling can also approve the current privileged request. Input-length verification does not establish that the password is correct; the system dialog decides that.

Photo checks can reject real users and cannot reliably stop replay attacks. Ordinary RGB face recognition can accept a photo or recorded video, especially with checks off.

## Supported dialogs

- Privacy & Security system settings password prompts.
- Native Passwords AutoFill verification, including AutoFill for Dia. Matching currently depends on English dialog text and the current account.

The app verifies supported Apple processes and dialog context. Arbitrary website password forms, lock-screen unlocking, passkeys, and Apple Pay approval are outside this beta's supported flow.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No camera image | Check Camera permission, select the intended device, and run Test camera. |
| Enrollment stops | Use steady lighting, keep your face close enough, and turn gently. Restart enrollment after a timeout. Beta 2 addresses the camera-start crash; report any remaining crash with its version and steps. |
| Nothing triggers | Unlock the session, enroll a face, check Accessibility permission, enable filling, and focus an empty supported system password field. |
| Dia works but another prompt does not | Check whether the prompt is supported and in English. Include the dialog type in a bug report with private details removed. |
| Failed attempt will not retry | Choose Retry current prompt or use the failure-island hover action. |
| Session is locked after sleep | Unlock it and enable filling again. This is expected. |
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
