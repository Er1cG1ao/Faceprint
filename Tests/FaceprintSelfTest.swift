import Foundation

@main
enum FaceprintSelfTest {
    static func main() throws {
        for unlocked in [false, true] {
            for face in [false, true] {
                for password in [false, true] {
                    for busy in [false, true] {
                        let expected = unlocked && face && password && !busy
                        precondition(InputActionPolicy.canEnable(dataSessionReady: unlocked, hasFace: face, hasPassword: password, busy: busy) == expected)
                    }
                }
            }
        }
        var readiness = PasswordFieldReadiness()
        precondition(!readiness.observe(sameField: false, focusedAndEmpty: true, now: 0.1))
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.61), "Initial animation grace must pass")
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: false, now: 0.7), "Losing focus resets readiness")
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 0.8))
        precondition(!readiness.observe(sameField: false, focusedAndEmpty: true, now: 1.2), "A recreated field must settle again")
        precondition(!readiness.observe(sameField: true, focusedAndEmpty: true, now: 1.6))
        precondition(readiness.observe(sameField: true, focusedAndEmpty: true, now: 1.71))
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
        var access = SettingsAccessState()
        precondition(!access.isUnlocked)
        let first = access.beginAuthorization()
        access.lock()
        precondition(!access.completeAuthorization(first), "A late authentication must not reopen locked settings")
        let second = access.beginAuthorization()
        precondition(access.completeAuthorization(second) && access.isUnlocked)
        access.lock()
        precondition(!access.isUnlocked)
        precondition(InputActionPolicy.canEnable(dataSessionReady: true, hasFace: true, hasPassword: true, busy: false), "Settings lock must not block ready autofill")
        for unlocked in [false, true] {
            for busy in [false, true] {
                precondition(InputActionPolicy.canChangeSettings(settingsUnlocked: unlocked, busy: busy) == (unlocked && !busy))
            }
        }
        print("PASS default settings lock, stale authentication rejection, edit authorization, and autofill independence")

        for enabled in [false, true] {
            for verified in [false, true] {
                precondition(InputActionPolicy.shouldPressReturn(enabled: enabled, verified: verified) == (enabled && verified))
            }
        }
        print("PASS filling requires a protected data session, a face, a password, and idle state; Return requires opt-in and verified input")

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
        precondition(PromptPolicy.biometricContext(in: unrelatedPrivacy, ownerBundleID: PromptPolicy.privacyBundleID) == nil)
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
        precondition(PromptPolicy.biometricContext(in: finderCard.map { $0.replacingOccurrences(of: "Finder", with: "Another App") }, ownerBundleID: "com.apple.SecurityAgent") == nil)
        let anotherFile = finderCard.map { $0.replacingOccurrences(of: "Keynote", with: "Other File") }
        precondition(PromptPolicy.biometricContext(in: anotherFile, ownerBundleID: "com.apple.SecurityAgent") != finderContext)
        precondition(!PromptPolicy.isSameFallbackRequest(originalPID: 12, passwordPID: 12, originalBundleID: "com.apple.SecurityAgent", passwordBundleID: "com.apple.SecurityAgent", originalContext: finderContext, passwordContext: "finder-trash:other file"))
        print("PASS Settings extension/agent hosts, Finder trash context, wrong host/app and changed-file rejection")
        print("PASS Touch ID prompt scope, fallback button labels, own-auth exclusion, and cross-request transition rejection")
        print("PASS native AutoFill context, wrong-account rejection, and session-prompt exclusion")
    }
}
