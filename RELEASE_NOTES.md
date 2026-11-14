# Faceprint 1.5.2

- Simplify the menu bar menu to Settings… and Quit Faceprint.
- Add Show in menu bar below Launch at login. It defaults on, persists across launches, and requires an unlocked settings session to change. Hiding the icon leaves automatic filling running.
- Keep native Launch Services reopening: launching the running Faceprint app opens and activates Settings, even with the menu icon hidden; a minimized settings window is restored. Settings also appears in the application menu with Command-comma.
- Publish the accumulated 1.3–1.5 changes: Glance-style settings/session layout and progressive blur, enrolled identity cards and post-capture naming, behavior/animation controls, no protected-data idle expiry, and verified GitHub updates with a separate installer/recovery copy. Sleep, screen lock, user switch, quit and editing-session authorization retain their protection.

Validation: existing recognition/prompt/authorization regressions; update metadata, archive, tamper rejection and temporary-directory 1.5.1 → 1.5.2 installation/recovery checks; optimized arm64 build and nested signature/archive verification. Native menu hiding/reopening and real GitHub update/permission behavior require installed-app verification.

This release is ad hoc signed and not Apple-notarized. Automatic updates are implemented, but TCC permission continuity still needs a compatible stable signing identity; this release may need Camera/Accessibility access again. Existing data is compatible with 1.5.1; earlier single-face data is imported on read. Older pre-identity versions cannot read face collections after they are saved in the new format.

# Faceprint 1.5.1 — test build

- Reuse Glance’s 80-point progressive header blur: three layered, gradient-masked backdrop materials fade from the window’s top edge to clear, behind the native traffic lights and Session capsule. The blur cannot intercept clicks or accessibility navigation.
- Shorten Passive photo checks, Scan Touch ID prompts and Press Return descriptions. Keep the system-change implication of automatic Return in the concise copy.
- Remove repeated session/recognition status footers across Settings and redundant Password/Camera/About captions. Keep update check/install state, attribution/license links and password-save errors. Move Copy diagnostics to the menu bar menu; status remains available in the menu bar tooltip.

Validation: optimized arm64 build, nested code signature, ZIP and existing updater package/installation checks. This change only affects settings presentation and diagnostics access; live scroll blur and native appearance need installed-app verification. No release was published.

# Faceprint 1.5.0 — test build

- Ask for a name after a new face's nine-direction capture, inside Glance's notch/pill flow. Save commits the identity; Back repeats capture; cancel/closing settings/session lock discards pending enrollment. Recapture keeps the existing identity's name. Existing identities are not renamed.
- Replace the camera pop-up with Glance's capsule menu treatment, neutral label and trailing chevrons.
- Add About → Check for Updates, a persisted automatic-check option (at most once daily after launch), download progress, and confirmed Install and Restart. Use the public GitHub latest stable Release; test ZIPs and prereleases are not automatically offered.
- Validate exact repository/asset/architecture/version URLs, GitHub SHA-256, bounded ZIP entry paths/kinds and expansion size, bundle metadata, macOS compatibility, arm64 executable and application code signatures before installation. A signed current app rejects updates with incompatible designated requirements. No unsigned fallback for signed apps.
- Install from a separate signed helper after the parent exits, reverify the downloaded archive and both applications, stage on the destination volume and atomically swap app bundles. Keep the previous signed app as a recovery copy; roll back if the relaunch command fails. Install only at writable Applications locations. Saved data and preferences are not moved or deleted.
- Support FACEPRINT_SIGN_IDENTITY when building, signing the helper before the app. Current builds remain ad hoc signed because no signing identity is available here. Automatic updates alone cannot preserve TCC permissions across ad hoc builds; a fixed compatible signing identity is still required. The first transition to that identity may need one more authorization.

Validation: existing prompt/input/enrollment regressions, update metadata/ZIP/signature/atomic-swap tests and temporary-directory old-to-new bundle installation; optimized arm64 build, nested signature and archive verification. No production app was replaced and no release was published. Live naming focus/animation, real GitHub download/restart and permission continuity still require installed-app verification; permission continuity is blocked on configuring a fixed signing certificate.

# Faceprint 1.4.0 — test build

- Correct the Session header's safe-area placement so it shares the native traffic-light header. Use Glance's small native switches.
- Move missing permissions to the top of General; hide the block once both are granted. Remove Session & data protection from General.
- Remove the protected-data session's 30-minute idle expiry. Sleep, screen lock, user switch and app quit still clear it; editing-session locking remains separate.
- Rename Recognition to Behavior. Add persisted Retry on notch hover and Auto retry once after failure switches. Automatic retry rediscovers the same signed request, requires a fresh face match, stops after one retry, respects cancellation, and never retries password-stage/input errors automatically.
- Replace the animation menu with Show animation plus Glance-style Minimal/Original preview tiles. Disabling animation hides automatic scan feedback without disabling filling; style preview yields to real requests and enrollment.
- Adapt Glance's enrolled-identity cards: names, enable switches, real per-sample capture-quality ticks, add, recapture and confirmed deletion. Store identities under the existing encrypted vault and match only enabled identities. Read legacy single-face data without deleting or overwriting it; legacy quality displays not recorded. New enrollment retains the existing nine-pose Glance flow and ArcFace model/thresholds.

Validation: retry-budget/cancellation policy, legacy/multi-identity serialization and enabled-only matching regressions plus existing prompt/input/enrollment checks; optimized arm64 build, signature and archive verification. Live header placement, animation/hover behavior, permissions and multi-identity enrollment require installed-app verification. This is an unreleased test build. Identity collection writes are forward-only for face data; older binaries do not understand newly saved multiple identities.

# Faceprint 1.3.1 — test build

- Show Faceprint in the Dock and Cmd-Tab while Settings is open; hide it when the window closes, keeping the menu bar app and enabled autofill running. Dock reopening restores Settings.
- Rename the editing authorization to Session. Show a centered Session locked / Unlock session screen and a header Session locked/unlocked capsule. The separate protected autofill data session and existing authentication/timeout policies are unchanged.
- Match Glance's 500 × 620 native unified-titlebar window, inset traffic lights, full-window material, 16-point content margins, compact 44-point simple rows and grouped filling/login controls. Remove large page headings and filling/login descriptions; retain right-aligned native switches with Glance's blue accent.
- Adapt Glance's measured tab-selection capsule and spring animation, including fading/sliding/blurred label reveal. Keep one scroll container across tab changes instead of rebuilding it.

Validation: policy and prompt regression tests, optimized arm64 build, ad hoc signature and ZIP verification. Dock/Cmd-Tab behavior and final visual/animation quality require verification in the installed app. Saved preferences, face templates and password data remain compatible.

# Faceprint 1.3.0 — test build

- Make settings edits depend on the editing unlock, independently of the autofill enabled preference and automatic recognition activity. Fresh settings authentication remains required; saved face/password prerequisites still apply to enabling filling.
- Coordinate enrollment and saved-password edits with active filling instead of requiring users to switch autofill off. Enrollment pauses automatic recognition and resumes it afterward while retaining the switch state. Password edits cancel a current automatic attempt without interrupting enrollment. Saved-data removal pauses probing during its confirmation and stops autofill only when removal is confirmed.
- Keep in-flight recognition/camera/style options as per-attempt snapshots. Turning automatic Return off before dispatch suppresses pending submission; turning it on does not retroactively submit an existing attempt.
- Reorder General's first cards: Settings unlock/lock, Enable face-assisted filling, Launch at login. Move all Recognition controls and protection information into General, and remove the Recognition tab.
- Move Camera/Accessibility permissions from Camera to General directly below Dynamic Island. Camera retains device selection and refresh.
- Use grouped rows with explanations inside each feature row and switches aligned at the trailing edge. Keep settings/data-session auto-lock durations unchanged.

Validation: editing authorization, enable prerequisites, live Return preference and existing regressions; build, signature and archive verification. Native enrollment/edit/fill interactions and final window appearance still require verification in the installed app. Existing preferences, face templates and encrypted data stay compatible.

# Faceprint 1.2.1

- Address the host handoff shown in the 1.2.0 diagnostic trace: com.apple.systempreferences owns the Touch ID card and com.apple.settings.PrivacySecurity.extension owns the focused password field. The generic cross-host window/geometry test rejected continuation before input.
- Permit only this directed native delegation after a successful explicit Use Password action, for the same Privacy context, with an empty currently focused secure field and a valid Apple signature. Require System Settings/the extension to be foreground, or the original requester to remain unchanged in front. Cross-XPC window metadata is not required for this fixed pair; other handoffs retain existing checks.
- Add a Settings-delegate-linked diagnostic phase and foreground/context/signature/focus flags on a failed handoff. Finder, browser AutoFill, recognition, input delivery and animation timing remain unchanged from 1.2.0.

Validation: reported-pair regression and negative cases for other hosts, contexts, missing fallback/focus/signature and changed foreground; existing self-tests, build, signature and archive checks. Live Settings filling still requires verification.

# Faceprint 1.2.0 — test build

- Expand English macOS account-authentication matching from individual Finder/Privacy strings to native SecurityAgent/LocalAuthentication requester/action and named continuation prompts, installer administrator forms, and matching System Settings extension panes. Keep Apple signature, system-location and request checks. Do not treat Apple Account, keychain, disk/recovery, passcode or website credentials as the saved Mac login password.
- Discover a single visible supported password field before it has keyboard focus; after recognizing the enrolled face, request focus before entering text. Prefer attached authentication sheets over underlying Settings pages.
- Move AX discovery, target validation, password transition/input and photo-feature extraction off the main actor; bound AX messaging timeouts and permit only one discovery task at a time. Keep generation/cancellation guards.
- Link Settings unlock/modify and System Settings/Privacy wording across stages. Bind continuation to the nearest authentication card rather than a large outer Settings window. Read AXNumberOfCharacters as well as AXValue length; refuse nonempty or unknown-length fields.
- Preload and warm the same ArcFace model, reuse camera configuration, overlap camera/model preparation and skip the unused capture-quality Vision pass when passive photo checks are off. Require two distinct consecutive matching frames with unchanged cosine thresholds; remove the fixed 250 ms match hold.
- Replace 500/750 ms password-card settling with a fresh 40 ms focused/empty-field confirmation, checked about every 16 ms. Use an explicit verified AXPress for Use Password, without a separate card-focus delay. Stop a failed password transition after 3 seconds.
- Assign the complete password through AXValue when the secure control supports it; otherwise preserve native keyboard delivery without artificial per-character sleeps. Verify delivery immediately and retry length reads only while needed, up to 180 ms. Optional Return still requires verified input.
- Reduce island entrance, pulse and collapse delays; prepare result video players ahead of time and play at 1.25x. Show Filling immediately after the face match; final success feedback follows verified delivery immediately, before optional Return dispatch. Shorten failure hold from 5 s to 1.2 s.
- Add Copy diagnostics below the Settings status. It copies only the most recent attempt's elapsed phase timings, host/role metadata and errors from memory. It does not copy passwords, prompt/file titles, frames, embeddings or vault data.

Validation: expanded native authentication/credential exclusions, distinct-frame matching, character-count handling, 40 ms readiness, request/host transition and existing regressions; build, signature and archive verification. Component timing uses synthetic Core ML input and excludes camera/Vision/AX. Live Settings/Finder/Dia workflow and visual latency still require verification; coverage is not universal for custom or differently worded dialogs. Saved data/model compatibility is unchanged.

# Faceprint 1.1.4 — test build

- Support Finder’s English “wants to make changes” authorization (including Undo) at both Touch ID and manually opened password stages, alongside the existing move-to-Trash request.
- Fix the original-process-only password lookup. A replacement Apple authentication host can continue a face-matched request only with the same context and exact request heading, plus the same AX window or matching card geometry after the original biometric stage disappears. Verify the replacement host’s Apple signature independently.
- Prioritize an already focused, verified password field; constrain background searches to the original card area instead of scanning unrelated large Settings windows.
- Preserve the focus/animation settling gate, empty-field verification, one-attempt scan behavior and optional Return after verified filling. No Return is used to reveal the password stage.

Validation: Finder changes/manual-password, ambiguous-heading and signed-host handoff regressions, existing self-tests, build, signature and ZIP checks. The host-handoff limitation is confirmed in code; the exact live Settings failure is not yet confirmed. Real system-dialog behavior remains to be verified on the user's Mac.

# Faceprint 1.1.3 — test build

- Keep face recognition, password-card mounting, focus and filling inside one attempt. Stop the camera once the enrolled face matches.
- After selecting Use Password with AXPress, discover the unique same-process/request secure field even when it initially lacks focus (for example Finder focusing its user-name field).
- Raise its window and request secure-field focus. Wait up to 7 seconds; require the same empty field to keep focus for 500 ms, with at least 750 ms since the transition, before reading or typing the saved password.
- Suppress a second automatic scan of the same request after a failed continuation, including short AX animation gaps. Use Retry current prompt for an explicit new attempt.
- Keep the independent automatic Return option after verified filling. No Return is sent to reveal the password card.

Validation: focus-settling/recreated-field and attempt-lifecycle regressions, existing self-tests, build, signature and ZIP verification. Real Finder/Settings animation and focus behavior remain to be verified on the user's Mac.

# Faceprint 1.1.2 — test build

- Recognize Settings authorization when hosted by System Settings, SecurityAgent or LocalAuthentication agents, alongside the Privacy & Security extension.
- Add the English Finder “wants to move … to the Trash” Touch ID and password flow. Keep the exact operation heading bound across the transition; unrelated requests and changed file operations are rejected.
- Resolve the actual AX fallback-button owner for XPC-hosted cards instead of assuming it is the application that exposes the window. Deduplicate the same card exposed by several hosts and inspect AXFocusedWindow when AXWindows omits it.
- Use HID input for supported Settings/Finder system authorization, retaining direct process input for the working Passwords AutoFill path.
- Show the focused system AX owner/role when no supported request matches; no password values are included.

Validation: automated host/context, Finder request and exclusion regressions, existing self-tests, build, signature and ZIP verification. Live system-window inspection was unavailable in this session. Settings/Finder triggering and actual password filling remain to be verified on the user's Mac. Existing user options, vault and face data are unchanged.

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
