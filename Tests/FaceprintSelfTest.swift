import Foundation

private func executingOnMainThread() -> Bool { Thread.isMainThread }

@main
enum FaceprintSelfTest {
    static func main() async throws {
        let isBackground = try await performPromptWork { !executingOnMainThread() }
        precondition(isBackground, "Prompt work must not block main-thread rendering")
        let cancelled = Task {
            try await performPromptWork {
                try await Task.sleep(for: .seconds(10))
                return true
            }
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled prompt work must not continue")
        } catch is CancellationError { }
        print("PASS background prompt work and cancellation propagation")
        for unlocked in [false, true] {
            for face in [false, true] {
                for password in [false, true] {
                    let expected = unlocked && face && password
                    precondition(InputActionPolicy.canEnable(dataSessionReady: unlocked, hasFace: face, hasPassword: password) == expected,
                        "Enabling depends on saved-data prerequisites; operation scheduling handles busy state")
                }
            }
        }
        var retry = AutomaticRetryBudget()
        precondition(!retry.claim(for: "a", enabled: false, recognitionFailed: true))
        precondition(!retry.claim(for: "a", enabled: true, recognitionFailed: false), "Never repeat password delivery")
        precondition(retry.claim(for: "a", enabled: true, recognitionFailed: true))
        precondition(!retry.claim(for: "a", enabled: true, recognitionFailed: true), "Only one automatic retry")
        retry.observeAbsence(now: 1)
        retry.observeAbsence(now: 1.5)
        precondition(!retry.claim(for: "a", enabled: true, recognitionFailed: true), "AX transition gap is not a new request")
        retry.observeAbsence(now: 2)
        retry.observeAbsence(now: 4.1)
        precondition(retry.claim(for: "a", enabled: true, recognitionFailed: true), "A dismissed/reopened request has a fresh budget")
        precondition(retry.claim(for: "b", enabled: true, recognitionFailed: true))
        retry.reset()
        precondition(retry.claim(for: "b", enabled: true, recognitionFailed: true), "Manual retry resets the budget")
        print("PASS one automatic recognition retry; no delivery retry, transition-gap reset or repeated retry loop")
        var faceGate = FaceMatchGate()
        precondition(!faceGate.observe(frame: 1, matched: true))
        precondition(!faceGate.observe(frame: 1, matched: true), "One frame cannot count twice")
        precondition(!faceGate.observe(frame: 2, matched: false))
        precondition(!faceGate.observe(frame: 3, matched: true))
        precondition(faceGate.observe(frame: 4, matched: true))
        precondition(InputActionPolicy.secureFieldLength(characterCount: 0, value: nil) == 0)
        precondition(InputActionPolicy.secureFieldLength(characterCount: nil, value: nil) == nil)
        precondition(InputActionPolicy.secureFieldLength(characterCount: 0, value: "••••") == 4, "A stale zero count must not permit overwriting a nonempty field")
        precondition(InputActionPolicy.secureFieldLength(characterCount: 4, value: "") == 4)
        precondition(InputActionPolicy.secureFieldLength(characterCount: -1, value: nil) == nil)
        print("PASS distinct-frame recognition, reset on mismatch, secure character-count fallback and nonempty rejection")
        var readiness = PasswordFieldReadiness()
        precondition(!readiness.observe(sameField: false, focusedAndEmpty: true, now: 0))
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.02))
        precondition(readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.041), "A focused field needs only a fresh confirmation")
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: false, now: 0.05))
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.06))
        precondition(!readiness.observe(sameField: false, focusedAndEmpty: true, now: 0.09))
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.11))
        precondition(readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.131))
        var attempts = PromptAttemptGate()
        precondition(attempts.observe("request-a", now: 0))
        attempts.mark("request-a")
        precondition(!attempts.observe("request-a", now: 1), "Password stage must not start a second face scan")
        precondition(!attempts.observe(nil, now: 1.1))
        precondition(!attempts.observe("request-a", now: 2), "An animation gap must not reset the attempt")
        precondition(attempts.observe("request-b", now: 2.1), "Unrelated requests remain independent")
        attempts.reset()
        precondition(attempts.observe("request-a", now: 2.2), "Explicit retry resets the attempt")
        attempts.mark("request-a")
        _ = attempts.observe(nil, now: 3)
        _ = attempts.observe(nil, now: 5.1)
        precondition(attempts.observe("request-a", now: 5.2), "A dismissed request can be used again")
        print("PASS transition focus settling, recreated-field delay, one scan across stages, retry and dismissal")
        for unlocked in [false, true] {
            for authenticating in [false, true] {
                precondition(InputActionPolicy.canChangeSettings(settingsUnlocked: unlocked, authenticating: authenticating) == (unlocked && !authenticating))
            }
        }
        print("PASS unlocked editing independent of autofill preference and recognition busy state; authentication stays gated")
        var access = SettingsAccessState()
        precondition(!access.isUnlocked)
        let first = access.beginAuthorization()
        access.lock()
        precondition(!access.completeAuthorization(first), "A late authentication must not reopen locked settings")
        let second = access.beginAuthorization()
        precondition(access.completeAuthorization(second) && access.isUnlocked)
        access.lock()
        precondition(!access.isUnlocked)
        precondition(InputActionPolicy.canEnable(dataSessionReady: true, hasFace: true, hasPassword: true), "Settings lock must not block ready autofill")
        print("PASS default settings lock, stale authentication rejection, edit authorization, and autofill independence")

        for enabledAtStart in [false, true] {
            for enabledNow in [false, true] {
                for verified in [false, true] {
                    precondition(InputActionPolicy.shouldPressReturn(enabledAtStart: enabledAtStart, enabledNow: enabledNow, verified: verified) == (enabledAtStart && enabledNow && verified))
                }
            }
        }
        precondition(!InputActionPolicy.shouldPressReturn(enabledAtStart: true, enabledNow: false, verified: true), "Turning Return off while filling must prevent submission")
        precondition(!InputActionPolicy.shouldPressReturn(enabledAtStart: false, enabledNow: true, verified: true), "Turning Return on must not submit an already-running attempt")
        print("PASS enabling requires protected data/face/password independent of execution state; Return requires opt-in and verified input")

        let poses: [(EnrollmentPose, Float, Float)] = [
            (.center, 0, 0), (.left, 0.3, 0), (.topLeft, 0.3, -0.22),
            (.top, 0, -0.22), (.topRight, -0.3, -0.22), (.right, -0.3, 0),
            (.bottomRight, -0.3, 0.22), (.bottom, 0, 0.22), (.bottomLeft, 0.3, 0.22)
        ]
        precondition(poses.map { $0.0 } == EnrollmentPose.allCases)
        for (pose, yaw, pitch) in poses {
            precondition(EnrollmentPoseMatcher.matches(yaw: yaw, pitch: pitch, pose: pose, widened: false))
            precondition(!EnrollmentPoseMatcher.matches(yaw: 0.7, pitch: 0.6, pose: pose, widened: true))
        }
        precondition(!EnrollmentPoseMatcher.matches(yaw: 0.22, pitch: 0, pose: .center, widened: false))
        precondition(EnrollmentPoseMatcher.matches(yaw: 0.22, pitch: 0, pose: .center, widened: true))
        print("PASS nine-pose order, capture bands, overshoot rejection, and stall widening")

        var vector = [Float](repeating: 0, count: 512)
        vector[0] = 1
        let legacy = try JSONSerialization.data(withJSONObject: [
            "modelIdentifier": "arcface-w600k_mbf-v1",
            "samples": Array(repeating: vector, count: 24)
        ])
        let decoded = try JSONDecoder().decode(FaceTemplate.self, from: legacy)
        precondition(decoded.poses == nil && decoded.matches(vector))
        let names = poses.flatMap { [$0.0.name, $0.0.name] }
        let template = FaceTemplate(modelIdentifier: "arcface-w600k_mbf-v1", samples: Array(repeating: vector, count: 18), poses: names)
        let restored = try JSONDecoder().decode(FaceTemplate.self, from: JSONEncoder().encode(template))
        precondition(restored.matches(vector) && restored.poses == names)
        print("PASS legacy face templates and nine-view serialization")

        let migrated = try FaceIdentityCollection.decode(legacy)
        precondition(migrated.identities.count == 1 && migrated.matches(vector))
        precondition(migrated.identities[0].template.qualities == nil)
        var other = [Float](repeating: 0, count: 512); other[1] = 1
        let otherTemplate = FaceTemplate(modelIdentifier: "arcface-w600k_mbf-v1", samples: Array(repeating: other, count: 18),
                                         poses: names, qualities: Array(repeating: 0.7, count: 18))
        var faces = migrated
        faces.identities.append(FaceIdentity(name: "Glasses", template: otherTemplate))
        precondition(faces.matches(other) && faces.matches(vector))
        faces.identities[0].isEnabled = false
        precondition(!faces.matches(vector) && faces.matches(other), "Disabled identities must never authorize filling")
        let multi = try FaceIdentityCollection.decode(JSONEncoder().encode(faces))
        precondition(multi.identities.map(\.id) == faces.identities.map(\.id))
        precondition(multi.identities[1].template.qualities == Array(repeating: Float(0.7), count: 18))
        faces.identities.removeLast()
        precondition(!faces.matches(other) && !faces.matches(vector), "Removed/all-disabled faces must not match")
        do {
            _ = try FaceIdentityCollection.decode(Data("{broken".utf8))
            preconditionFailure("Corrupt stores must not be treated as an empty enrollment")
        } catch { }
        let unknown = try JSONSerialization.data(withJSONObject: ["version": 99, "identities": []])
        do {
            _ = try FaceIdentityCollection.decode(unknown)
            preconditionFailure("Unknown store versions must fail closed")
        } catch { }
        print("PASS legacy migration, encrypted-payload identity serialization, enabled-only matching, deletion and corrupt-store rejection")

        for text in ["x", "abc123!", "A😀Bé", String(repeating: "z", count: 21) + "😀👩‍💻"] {
            for limit in [1, 20] {
                let chunks = KeyboardText.batches(text, maximumUTF16Units: limit)
                precondition(chunks.flatMap { $0 } == Array(text.utf16))
                precondition(chunks.allSatisfy { !($0.last.map { (0xD800...0xDBFF).contains($0) } ?? false) })
            }
        }
        print("PASS Unicode input chunks preserve surrogate pairs")

        let prompt = ["AutoFill for “Example Browser”", "Enter the password for the user “Test User” to continue with Passwords.", "OK", "Cancel"]
        precondition(PromptPolicy.autofillContext(in: prompt, accountNames: ["Test User"]) == "autofill:example browser")
        precondition(PromptPolicy.autofillContext(in: prompt, accountNames: ["Another User"]) == nil)
        precondition(PromptPolicy.autofillContext(in: ["Open your Faceprint session", "OK", "Cancel"], accountNames: ["Test User"]) == nil)
        let privacyBiometric = ["Privacy & Security is trying to modify your system settings.",
                                "Touch ID or enter your password to continue with Privacy & Security.", "Use Password…", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: privacyBiometric, ownerBundleID: PromptPolicy.privacyBundleID) == "privacy")
        precondition(PromptPolicy.biometricContext(in: privacyBiometric, ownerBundleID: "example.fake") == nil)
        precondition(PromptPolicy.biometricContext(in: privacyBiometric.filter { $0 != "Use Password…" }, ownerBundleID: PromptPolicy.privacyBundleID) == nil)
        precondition(PromptPolicy.biometricContext(in: privacyBiometric.filter { !$0.contains("Touch ID") }, ownerBundleID: PromptPolicy.privacyBundleID) == nil)
        let unlockBiometric = privacyBiometric.map { $0.replacingOccurrences(of: "modify your system settings", with: "unlock system settings") }
        precondition(PromptPolicy.biometricContext(in: unlockBiometric, ownerBundleID: PromptPolicy.privacyBundleID) == "privacy")
        let unrelatedPrivacy = privacyBiometric.map { $0.replacingOccurrences(of: "modify your system settings", with: "change an unrelated account") }
        precondition(PromptPolicy.biometricContext(in: unrelatedPrivacy, ownerBundleID: PromptPolicy.privacyBundleID)?.hasPrefix("native:") == true)
        let autofillBiometric = ["AutoFill for “Example Browser”", "Use Touch ID to continue with Passwords.", "Use Password...", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: autofillBiometric, ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == "autofill:example browser")
        for title in ["Unlock to modify Faceprint settings", "Resume Faceprint autofill", "Authorize another app"] {
            precondition(PromptPolicy.biometricContext(in: [title, "Touch ID", "Use Password…", "Cancel"], ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == nil)
        }
        precondition(PromptPolicy.biometricContext(in: prompt, ownerBundleID: "com.apple.Passwords") == nil, "Password stage must not be mistaken for Touch ID")
        precondition(!PromptPolicy.isPasswordFallbackButton("Do not use password"))
        precondition(!PromptPolicy.isPasswordFallbackButton("Use Password and approve"))
        precondition(PromptPolicy.isSameFallbackRequest(originalPID: 12, passwordPID: 12, originalBundleID: "apple", passwordBundleID: "apple", originalContext: "privacy", passwordContext: "privacy"))
        for (pid, bundle, context) in [(Int32(13), "apple", "privacy"), (Int32(12), "other", "privacy"), (Int32(12), "apple", "autofill:other")] {
            precondition(!PromptPolicy.isSameFallbackRequest(originalPID: 12, passwordPID: pid, originalBundleID: "apple", passwordBundleID: bundle, originalContext: "privacy", passwordContext: context))
        }
        for owner in ["com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent", "com.apple.LocalAuthenticationRemoteService"] {
            precondition(PromptPolicy.biometricContext(in: unlockBiometric, ownerBundleID: owner) == "privacy")
            let passwordStage = unlockBiometric.filter { !$0.contains("Touch ID") && $0 != "Use Password…" } + ["Enter your password to continue with Privacy & Security."]
            precondition(PromptPolicy.systemDialogContext(in: passwordStage, ownerBundleID: owner) == "privacy")
        }
        let finderCard = ["Finder wants to move “Keynote” to the Trash.",
                          "Touch ID or enter your password to continue with “Finder”.", "Use Password…", "Cancel"]
        let finderContext = "finder-trash:finder wants to move \"keynote\" to the trash."
        for owner in ["com.apple.finder", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent"] {
            precondition(PromptPolicy.biometricContext(in: finderCard, ownerBundleID: owner) == finderContext)
            let passwordCard = [finderCard[0], "Enter your password to continue with “Finder”.", "Move to Trash", "Cancel"]
            precondition(PromptPolicy.systemDialogContext(in: passwordCard, ownerBundleID: owner) == finderContext)
        }
        precondition(PromptPolicy.biometricContext(in: finderCard, ownerBundleID: "example.fake") == nil)
        precondition(PromptPolicy.biometricContext(in: finderCard, ownerBundleID: PromptPolicy.privacyBundleID) == nil)
        precondition(PromptPolicy.biometricContext(in: finderCard.map { $0.replacingOccurrences(of: "Finder", with: "Another App") }, ownerBundleID: "com.apple.SecurityAgent")?.hasPrefix("native:") == true)
        let anotherFile = finderCard.map { $0.replacingOccurrences(of: "Keynote", with: "Other File") }
        precondition(PromptPolicy.biometricContext(in: anotherFile, ownerBundleID: "com.apple.SecurityAgent") != finderContext)
        precondition(!PromptPolicy.isSameFallbackRequest(originalPID: 12, passwordPID: 12, originalBundleID: "com.apple.SecurityAgent", passwordBundleID: "com.apple.SecurityAgent", originalContext: finderContext, passwordContext: "finder-trash:other file"))
        let changesCard = ["Finder wants to make changes.", "Touch ID or enter your password to continue with “Finder”.", "Use Password…", "Cancel"]
        let changesPassword = ["Finder wants to make changes.", "Enter your password to continue with “Finder”.", "OK", "Cancel"]
        for owner in ["com.apple.finder", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent"] {
            precondition(PromptPolicy.biometricContext(in: changesCard, ownerBundleID: owner) == "finder-changes")
            precondition(PromptPolicy.systemDialogContext(in: changesPassword, ownerBundleID: owner) == "finder-changes")
        }
        precondition(PromptPolicy.biometricContext(in: changesCard, ownerBundleID: "example.fake") == nil)
        precondition(PromptPolicy.systemDialogContext(in: changesPassword.map { $0.replacingOccurrences(of: "“Finder”", with: "“Another App”") }, ownerBundleID: "com.apple.SecurityAgent") == nil)
        precondition(PromptPolicy.requestHeading(in: unlockBiometric) == "privacy & security is trying to unlock system settings.")
        precondition(PromptPolicy.requestHeading(in: ["Privacy & Security is trying to unlock system settings. Enter your password to continue."]) == PromptPolicy.requestHeading(in: unlockBiometric))
        precondition(PromptPolicy.requestHeading(in: ["Finder wants to make changes.", "Privacy & Security is trying to unlock system settings."]) == nil)
        precondition(PromptPolicy.permitsHostHandoff(sameContext: true, sameHeading: true, sameWindow: false, matchingFrame: true, originalBiometricGone: true, appleSigned: true))
        precondition(PromptPolicy.permitsHostHandoff(sameContext: true, sameHeading: true, sameWindow: true, matchingFrame: false, originalBiometricGone: false, appleSigned: true))
        for (context, heading, geometry, gone, signed) in [(false,true,true,true,true), (true,false,true,true,true), (true,true,false,true,true), (true,true,true,false,true), (true,true,true,true,false)] {
            precondition(!PromptPolicy.permitsHostHandoff(sameContext: context, sameHeading: heading, sameWindow: false, matchingFrame: geometry, originalBiometricGone: gone, appleSigned: signed))
        }
        let installer = ["Installer is trying to install new software.", "Enter an administrator's name and password to allow this.", "Use Password…", "Touch ID or enter your password", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: installer, ownerBundleID: "com.apple.SecurityAgent")?.hasPrefix("native:installer") == true)
        precondition(PromptPolicy.systemDialogContext(in: installer.filter { $0 != "Use Password…" && !$0.hasPrefix("Touch ID") }, ownerBundleID: "com.apple.SecurityAgent")?.hasPrefix("native:installer") == true)
        let external = ["Example App wants to make changes.", "Touch ID or enter your password to continue with “Example App”.", "Use Password…", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: external, ownerBundleID: "com.apple.LocalAuthentication.UIAgent")?.hasPrefix("native:example app") == true)
        precondition(PromptPolicy.biometricContext(in: external, ownerBundleID: "example.app") == nil)
        let continuationOnly = ["Touch ID or enter your password to continue with “Example Service”.", "Use Password…", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: continuationOnly, ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == "native:macos account authentication for example service")
        let passwordOnly = ["Enter your password to continue with “Example Service”.", "OK", "Cancel"]
        precondition(PromptPolicy.systemDialogContext(in: passwordOnly, ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == "native:macos account authentication for example service")
        precondition(PromptPolicy.nativeAuthenticationContext(in: continuationOnly + ["Enter your password to continue with “Another Service”."], ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == nil)
        precondition(PromptPolicy.supportsOwner("com.apple.settings.Network.extension"))
        let network = ["Network wants to make changes.", "Touch ID or enter your password to continue with “Network”.", "Enter Password…", "Cancel"]
        precondition(PromptPolicy.biometricContext(in: network, ownerBundleID: "com.apple.settings.Network.extension")?.hasPrefix("native:network") == true)
        precondition(PromptPolicy.biometricContext(in: external, ownerBundleID: "com.apple.settings.Network.extension") == nil)
        let settingsHost = unlockBiometric.map { $0.replacingOccurrences(of: "Privacy & Security", with: "System Settings") }
        precondition(PromptPolicy.biometricContext(in: settingsHost, ownerBundleID: "com.apple.LocalAuthentication.UIAgent") == "privacy")
        precondition(PromptPolicy.compatibleHeadings("system settings is trying to unlock system settings.", "privacy & security is trying to modify your system settings.", context: "privacy"))
        for secret in ["keychain", "Apple Account", "Apple ID", "recovery key", "passcode", "Apple Pay", "disk password"] {
            precondition(PromptPolicy.nativeAuthenticationContext(in: external + [secret], ownerBundleID: "com.apple.SecurityAgent") == nil)
        }
        precondition(!PromptPolicy.compatibleHeadings("privacy & security is trying to unlock system settings.", "example app wants to make changes.", context: "privacy"))
        precondition(PromptPolicy.compatibleHeadings("privacy & security is trying to unlock system settings.", "privacy & security is trying to modify your system settings.", context: "privacy"))
        // Reproduce the reported 1.2.0 handoff: verified Settings Touch ID card
        // -> focused empty PrivacySecurity extension field, across process IDs.
        // The directed delegation does not require shared AX window geometry.
        for foreground in ["com.apple.systempreferences", PromptPolicy.privacyBundleID] {
            precondition(PromptPolicy.permitsSettingsDelegateHandoff(originalBundleID: "com.apple.systempreferences", passwordBundleID: PromptPolicy.privacyBundleID, originalContext: "privacy", passwordContext: "privacy", fallbackSelected: true, focusedEmptyField: true, appleSigned: true, foregroundBundleID: foreground))
        }
        // macOS modal auth can retain its original requester's menu-bar owner.
        precondition(PromptPolicy.permitsSettingsDelegateHandoff(originalBundleID: "com.apple.systempreferences", passwordBundleID: PromptPolicy.privacyBundleID, originalContext: "privacy", passwordContext: "privacy", fallbackSelected: true, focusedEmptyField: true, appleSigned: true, foregroundBundleID: "io.github.er1cg1ao.faceprint", foregroundUnchanged: true))
        for (source, destination, sourceContext, targetContext, pressed, focusedEmpty, signed, foreground) in [
            ("com.apple.finder", PromptPolicy.privacyBundleID, "privacy", "privacy", true, true, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", "com.apple.LocalAuthentication.UIAgent", "privacy", "privacy", true, true, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "finder-changes", "privacy", true, true, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "privacy", "native:other", true, true, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "privacy", "privacy", false, true, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "privacy", "privacy", true, false, true, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "privacy", "privacy", true, true, false, "com.apple.systempreferences"),
            ("com.apple.systempreferences", PromptPolicy.privacyBundleID, "privacy", "privacy", true, true, true, "example.browser")
        ] {
            precondition(!PromptPolicy.permitsSettingsDelegateHandoff(originalBundleID: source, passwordBundleID: destination, originalContext: sourceContext, passwordContext: targetContext, fallbackSelected: pressed, focusedEmptyField: focusedEmpty, appleSigned: signed, foregroundBundleID: foreground))
        }
        precondition(!PromptPolicy.permitsSettingsDelegateHandoff(originalBundleID: "com.apple.systempreferences", passwordBundleID: PromptPolicy.privacyBundleID, originalContext: "privacy", passwordContext: "privacy", fallbackSelected: true, focusedEmptyField: true, appleSigned: true, foregroundBundleID: nil))
        print("PASS reported Settings-to-PrivacySecurity delegation; wrong-host/context, absent focus/action/signature and changed-foreground rejection")
        print("PASS native installer/app authentication, wrong-host/credential exclusions and Settings wording handoff")
        print("PASS Finder changes/undo stages, ambiguous headings, and constrained signed-host handoff")
        print("PASS Settings extension/agent hosts, Finder trash context, wrong host/app and changed-file rejection")
        print("PASS Touch ID prompt scope, fallback button labels, own-auth exclusion, and cross-request transition rejection")
        print("PASS native AutoFill context, wrong-account rejection, and session-prompt exclusion")
    }
}
