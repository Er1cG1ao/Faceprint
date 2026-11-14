import AppKit
import SwiftUI
import Combine
import AVFoundation
import Carbon
import LocalAuthentication

@MainActor
final class FillController: ObservableObject {
    @Published var status = "Session locked. Unlock to make changes."
    @Published private(set) var dataSessionReady = false
    @Published private(set) var settingsAccess = SettingsAccessState()
    @Published var protectionStatus = "Checking session protection…"
    @Published var promptStatus = "Supports native macOS account authentication and Passwords AutoFill prompts."
    @Published var hasFace = false
    @Published var hasPassword = SecureCredentialManager.hasStoredPassword()
    @Published var busy = false
    @Published var passwordDraft = ""
    @Published private(set) var automaticPasswordFallback = UserDefaults.standard.bool(forKey: "automaticPasswordFallback")
    @Published private(set) var passivePhotoChecks = UserDefaults.standard.bool(forKey: "passivePhotoChecks")
    @Published private(set) var islandStyle = GlanceSettings.shared.animationStyle {
        didSet { GlanceSettings.shared.animationStyle = islandStyle }
    }
    @Published private(set) var autoSubmit = UserDefaults.standard.bool(forKey: "autoSubmit") {
        didSet { UserDefaults.standard.set(autoSubmit, forKey: "autoSubmit") }
    }
    @Published private(set) var retryOnHover = GlanceSettings.shared.retryOnHover
    @Published private(set) var autoRetryOnce = UserDefaults.standard.bool(forKey: "autoRetryOnce")
    @Published private(set) var showAnimation = GlanceSettings.shared.showAnimation
    @Published private(set) var cameraID: String {
        didSet { UserDefaults.standard.set(cameraID, forKey: "cameraID") }
    }
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "fillingEnabled") {
        didSet {
            if !enabled && !isEnrolling && !authenticationInProgress { cancelOperation() }
            else if enabled && !isEnrolling { status = "Waiting for an empty supported system password field." }
        }
    }
    var onAuthenticationFinished: (() -> Void)?
    let camera: Camera
    let enrollment: OnboardingController
    @Published private(set) var identities: [FaceIdentity] = []
    private var previewTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryBudget = AutomaticRetryBudget()
    private var recognizer: Recognizer?
    private var recognizerLoad: Task<Recognizer, Error>?
    private var probing = false
    @Published private(set) var diagnosticTrace = ""
    private var traceStart: TimeInterval = 0
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var attemptedField: AXUIElement?
    private var attemptGate = PromptAttemptGate()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var screenLocked = false
    private var sleeping = false
    private var userSessionActive = true
    private var authenticationInProgress = false
    private var runtimeAuthenticationDeferred = false
    private var isEnrolling = false
    private var isEditingSavedData = false
    private var settingsLastActivity = Date()
    var settingsUnlocked: Bool { settingsAccess.isUnlocked }
    var canModifySettings: Bool { InputActionPolicy.canChangeSettings(settingsUnlocked: settingsUnlocked, authenticating: authenticationInProgress) }
    var canEditOptions: Bool { canModifySettings }
    var canUnlockSettings: Bool { !settingsUnlocked && !authenticationInProgress && !screenLocked && !sleeping && userSessionActive }
    var canEnrollFace: Bool { canEditOptions && dataSessionReady && !isEnrolling }
    var isEnrollingFace: Bool { isEnrolling }


    var canEnable: Bool { InputActionPolicy.canEnable(dataSessionReady: dataSessionReady, hasFace: hasFace, hasPassword: hasPassword) }

    init() {
        let previous = UserDefaults.standard.persistentDomain(forName: "local.giao.glancefill")
        cameraID = UserDefaults.standard.string(forKey: "cameraID") ?? previous?["cameraID"] as? String ?? ""
        let camera = Camera()
        self.camera = camera
        self.enrollment = OnboardingController(camera: camera)
        enrollment.onCancel = { [weak self] in
            self?.cancelOperation()
            self?.status = "Enrollment cancelled."
        }
        Task {
            do {
                try await Task.detached { try SecureCredentialManager.checkProtectionAvailability() }.value
                protectionStatus = "Secure Enclave protection available."
            } catch {
                protectionStatus = "Session protection check: \(error.localizedDescription)"
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.sleeping = true; self?.endRuntimeSession() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.userSessionActive = false; self?.endRuntimeSession() } })
        screenObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.screenLocked = true; self?.endRuntimeSession() } }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.sleeping = false } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.userSessionActive = true } })
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.screenLocked = false } }

        recognizerLoad = Task.detached(priority: .userInitiated) { try Recognizer() }

    }

    func unlockSettings() {
        guard canUnlockSettings else { return }
        // Editing authentication can interrupt an automatic scan; the user's
        // enabled preference remains intact and resumes after authentication.
        cancelOperation()
        attemptedField = nil
        attemptGate.reset()
        let ticket = settingsAccess.beginAuthorization()
        let currentGeneration = generation
        authenticationInProgress = true
        busy = true
        status = "Authenticate to modify Faceprint settings…"
        Task {
            let context = LAContext()
            context.touchIDAuthenticationAllowableReuseDuration = 0
            defer {
                context.invalidate()
                authenticationInProgress = false
                busy = false
                onAuthenticationFinished?()
            }
            do {
                // Always authenticate, even if autofill already holds a data-session key.
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                        localizedReason: "Unlock the Faceprint session to modify settings") else {
                    throw FillError.message("Authentication was not completed.")
                }
                guard settingsAccess.accepts(ticket), generation == currentGeneration else { return }
                try await Task.detached {
                    try SecureCredentialManager.unlockSession(reason: "Open Faceprint's encrypted data", authenticationContext: context)
                }.value
                guard generation == currentGeneration else { SecureCredentialManager.lockSession(); return }
                try loadRuntimeData()
                guard settingsAccess.completeAuthorization(ticket) else { return }
                settingsLastActivity = Date()
                runtimeAuthenticationDeferred = false
                status = "Session unlocked. Changes are now allowed."
            } catch {
                status = "Settings remain locked: \(error.localizedDescription)"
            }
        }
    }

    func lockSettings() {
        settingsAccess.lock()
        passwordDraft = ""
        if isEnrolling { cancelOperation() }
        status = enabled ? "Session locked. Autofill remains enabled." : "Session locked."
    }

    private func loadRuntimeData() throws {
        identities = try SecureFaceStore.loadIdentities()
        hasFace = identities.contains { $0.isEnabled }
        hasPassword = SecureCredentialManager.hasStoredPassword()
        dataSessionReady = true
    }

    func resumeAutofill() {
        guard enabled, !dataSessionReady, !busy, !authenticationInProgress, !screenLocked, !sleeping, userSessionActive else { return }
        let currentGeneration = generation
        authenticationInProgress = true
        busy = true
        status = "Authenticate once to resume protected autofill…"
        Task {
            defer { authenticationInProgress = false; busy = false }
            do {
                try await Task.detached {
                    try SecureCredentialManager.unlockSession(reason: "Resume Faceprint autofill")
                }.value
                guard generation == currentGeneration else { SecureCredentialManager.lockSession(); return }
                try loadRuntimeData()
                runtimeAuthenticationDeferred = false
                attemptedField = nil
                status = "Autofill ready. Settings remain locked until you unlock them to edit."
            } catch {
                runtimeAuthenticationDeferred = true
                status = "Autofill paused: \(error.localizedDescription) Use Resume autofill to try again."
            }
        }
    }

    func endRuntimeSession() {
        lockSettings()
        cancelOperation()
        identities = []
        hasFace = false
        dataSessionReady = false
        runtimeAuthenticationDeferred = false
        SecureCredentialManager.lockSession()
        status = enabled ? "Protected data locked. Autofill will request authentication when needed." : "Session locked."
    }

    func setEnabled(_ value: Bool) {
        guard canModifySettings, !value || canEnable else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "fillingEnabled")
        settingsLastActivity = Date()
    }

    func setCameraID(_ value: String) {
        guard canEditOptions else { return }
        cameraID = value
        settingsLastActivity = Date()
    }

    func setIslandStyle(_ value: UnlockAnimationStyle) {
        guard canEditOptions else { return }
        islandStyle = value
        settingsLastActivity = Date()
    }

    func setAutoSubmit(_ value: Bool) {
        guard canEditOptions else { return }
        autoSubmit = value
        settingsLastActivity = Date()
    }

    func setAutomaticPasswordFallback(_ value: Bool) {
        guard canEditOptions else { return }
        automaticPasswordFallback = value
        UserDefaults.standard.set(value, forKey: "automaticPasswordFallback")
        settingsLastActivity = Date()
    }

    func setPhotoChecks(_ value: Bool) {
        guard canEditOptions else { return }
        passivePhotoChecks = value
        UserDefaults.standard.set(value, forKey: "passivePhotoChecks")
        settingsLastActivity = Date()
    }

    func savePassword(_ password: String) throws {
        guard canEditOptions, dataSessionReady else { throw FillError.message("Unlock settings before changing your password.") }
        guard !password.isEmpty else { throw FillError.message("Enter your Mac login password first.") }
        guard !password.contains(where: { $0.isNewline || $0 == "\t" }) else {
            throw FillError.message("The password contains an unsupported control character.")
        }
        prepareProtectedDataEdit()
        var data = Data(password.utf8)
        defer { data.resetBytes(in: 0..<data.count) }
        try SecureCredentialManager.savePassword(data)
        hasPassword = true
        settingsLastActivity = Date()
        status = "Password encrypted and saved."
    }

    func selectAnimation(_ style: UnlockAnimationStyle) {
        guard canEditOptions, showAnimation else { return }
        setIslandStyle(style)
        guard !busy else { return }
        previewTask?.cancel()
        let token = generation
        NotchOverlayController.shared.present(styleOverride: style)
        previewTask = Task {
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard !Task.isCancelled, token == generation, !busy,
                  NotchOverlayController.shared.phase == .scanning else { return }
            NotchOverlayController.shared.finish(success: true)
        }
    }

    func setRetryOnHover(_ value: Bool) {
        guard canEditOptions else { return }
        retryOnHover = value; GlanceSettings.shared.retryOnHover = value
        settingsLastActivity = Date()
    }
    func setAutoRetryOnce(_ value: Bool) {
        guard canEditOptions else { return }
        autoRetryOnce = value; UserDefaults.standard.set(value, forKey: "autoRetryOnce")
        if !value { retryTask?.cancel(); retryTask = nil }
        settingsLastActivity = Date()
    }
    func setShowAnimation(_ value: Bool) {
        guard canEditOptions else { return }
        showAnimation = value; GlanceSettings.shared.showAnimation = value
        if !value, !busy {
            previewTask?.cancel(); previewTask = nil
            NotchOverlayController.shared.dismissImmediately()
        }
        settingsLastActivity = Date()
    }
    func setIdentityEnabled(_ id: UUID, enabled value: Bool) {
        guard canEditOptions, dataSessionReady, !isEnrolling else { return }
        var updated = identities
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isEnabled = value
        saveIdentities(updated)
    }
    func deleteIdentity(_ id: UUID) {
        guard canEditOptions, dataSessionReady, !isEnrolling else { return }
        saveIdentities(identities.filter { $0.id != id })
    }
    private func saveIdentities(_ updated: [FaceIdentity]) {
        prepareProtectedDataEdit()
        do {
            try SecureFaceStore.saveIdentities(updated)
            identities = updated
            hasFace = updated.contains { $0.isEnabled }
            settingsLastActivity = Date()
            status = "Enrolled faces updated."
        } catch { status = error.localizedDescription }
    }

    func retry() {
        guard enabled, !busy else { return }
        retryTask?.cancel(); retryTask = nil; retryBudget.reset()
        attemptedField = nil
        attemptGate.reset()
        runtimeAuthenticationDeferred = false
        status = "Retrying the current supported prompt."
    }

    private func cancelOperation() {
        generation &+= 1
        retryTask?.cancel(); retryTask = nil; retryBudget.reset()
        previewTask?.cancel(); previewTask = nil
        operation?.cancel()
        operation = nil
        camera.stop()
        enrollment.dismiss()
        NotchOverlayController.shared.dismissImmediately()
        busy = false
        isEnrolling = false
    }

    /// Interrupt an automatic fill before editing protected data, without
    /// requiring the user to turn filling off. Password updates can coexist
    /// with enrollment; vault writes are serialized by SecureCredentialManager.
    private func prepareProtectedDataEdit(cancelEnrollment: Bool = false) {
        guard !isEnrolling || cancelEnrollment else { return }
        cancelOperation()
        attemptedField = nil
        attemptGate.reset()
    }

    private func getRecognizer() async throws -> Recognizer {
        if let recognizer { return recognizer }
        let loading = recognizerLoad ?? Task.detached(priority: .userInitiated) { try Recognizer() }
        recognizerLoad = loading
        let loaded = try await loading.value
        recognizer = loaded
        return loaded
    }

    func enroll(identityID: UUID? = nil) {
        guard canEnrollFace else { return }
        prepareProtectedDataEdit()
        isEnrolling = true
        busy = true
        generation &+= 1
        let currentGeneration = generation
        status = "Follow the nine-direction guide in the Dynamic Island."
        let deviceID = cameraID
        operation = Task {
            do {
                let recognizer = try await getRecognizer()
                try Task.checkCancellation()
                var captured: FaceTemplate?
                var capturedName: String?
                while captured == nil {
                    let saved = try await enrollment.capture(using: recognizer, deviceID: deviceID)
                    try Task.checkCancellation()
                    if identityID == nil {
                        do {
                            capturedName = try await enrollment.nameCapturedFace(suggestedName: NSFullUserName())
                        } catch EnrollmentNameAction.recapture { continue }
                    }
                    captured = saved
                }
                try Task.checkCancellation()
                guard settingsUnlocked, let saved = captured else { throw CancellationError() }
                var updated = identities
                if let identityID {
                    guard let index = updated.firstIndex(where: { $0.id == identityID }) else { throw CancellationError() }
                    updated[index].template = saved
                } else {
                    guard let capturedName, !capturedName.isEmpty else { throw CancellationError() }
                    updated.append(FaceIdentity(name: capturedName, template: saved))
                }
                try SecureFaceStore.saveIdentities(updated)
                identities = updated
                hasFace = updated.contains { $0.isEnabled }
                settingsLastActivity = Date()
                status = "All nine views enrolled. Face recognition is ready."
            } catch {
                if !Task.isCancelled { status = error.localizedDescription }
            }
            if generation == currentGeneration {
                camera.stop()
                enrollment.dismiss()
                isEnrolling = false
                busy = false
                operation = nil
            }
        }
    }

    private func poll() {
        if settingsUnlocked, !isEnrolling, Date().timeIntervalSince(settingsLastActivity) >= 5 * 60 {
            lockSettings()
        }
        guard enabled, !busy, !isEditingSavedData, !screenLocked, !sleeping, userSessionActive else { return }
        guard !probing else { return }
        guard AXIsProcessTrusted() else {
            status = "Grant Faceprint Accessibility access, then enable filling again."
            enabled = false
            return
        }
        let token = generation
        let allowBiometric = automaticPasswordFallback
        probing = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let target = FillTrigger.current(allowBiometric: allowBiometric)
                let verified = target?.verifyAppleSignature() == true
                let diagnostic = target == nil ? PromptTarget.diagnosticSummary() : nil
                return (verified ? target : nil, diagnostic)
            }.value
            probing = false
            guard token == generation, enabled, !busy, !isEditingSavedData, !screenLocked, !sleeping, userSessionActive else { return }
            guard let trigger = result.0 else {
                _ = attemptGate.observe(nil, now: Date.timeIntervalSinceReferenceDate)
                retryBudget.observeAbsence(now: Date.timeIntervalSinceReferenceDate)
                if let diagnostic = result.1 { promptStatus = diagnostic }
                return
            }
            if !dataSessionReady {
                if !runtimeAuthenticationDeferred { resumeAutofill() }
                return
            }
            handleTrigger(trigger)
        }
    }

    private func record(_ event: String) {
        let line = String(format: "%.3fs %@", ProcessInfo.processInfo.systemUptime - traceStart, event)
        diagnosticTrace += (diagnosticTrace.isEmpty ? "" : "\n") + line
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        NSPasteboard.general.setString("Faceprint \(version) — most recent attempt\n" + diagnosticTrace, forType: .string)
    }

    private func handleTrigger(_ trigger: FillTrigger) {
        let templates = FaceIdentityCollection(identities: identities)
        guard identities.contains(where: { $0.isEnabled }) else { return }
        retryBudget.observe(trigger.requestKey)
        promptStatus = "Recognized \(trigger.description) prompt."
        guard attemptGate.observe(trigger.requestKey, now: Date.timeIntervalSinceReferenceDate) else { return }
        if let attemptedField, CFEqual(attemptedField, trigger.element) { return }
        attemptedField = trigger.element
        busy = true
        previewTask?.cancel(); previewTask = nil
        generation &+= 1
        let currentGeneration = generation
        let usePhotoChecks = passivePhotoChecks
        let useAnimation = showAnimation
        let useAutoRetry = autoRetryOnce
        let useAutomaticReturn = autoSubmit
        let deviceID = cameraID
        traceStart = ProcessInfo.processInfo.systemUptime
        diagnosticTrace = ""
        record("Detected verified \(trigger.description) prompt")
        let report: @Sendable (String) -> Void = { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.record(event)
                if self.busy { self.status = event }
            }
        }
        status = "Looking for your face…"
        if useAnimation {
            NotchOverlayController.shared.present(onRetry: { [weak self] in self?.retry() })
        }
        operation = Task {
            var recognitionFailed = false
            var handedOff = false
            do {
                guard try await performPromptWork({ trigger.isCurrent() }) else { throw CancellationError() }
                async let cameraReady: Void = camera.start(deviceID: deviceID)
                let recognizer = try await getRecognizer()
                try await cameraReady
                record("Camera and recognition model ready")
                try Task.checkCancellation()
                let liveness = LivenessAnalyzer()
                liveness.modeProvider = { .light }
                var matchGate = FaceMatchGate()
                var receivedFirstInference = false
                var lastFrame: UInt64?
                var receivedFirstFrame = false
                let deadline = Date().addingTimeInterval(12)
                var filled = false
                while Date() < deadline {
                    try Task.checkCancellation()
                    guard try await performPromptWork({ trigger.isCurrent() }) else {
                        throw FillError.message("Prompt changed. Return to the supported prompt and choose Retry from the menu.")
                    }
                    guard let frame = camera.latestFrame(), frame.id != lastFrame else {
                        try await Task.sleep(nanoseconds: 30_000_000)
                        continue
                    }
                    lastFrame = frame.id
                    if !receivedFirstFrame { record("First camera frame received"); receivedFirstFrame = true }
                    let inferenceStart = ProcessInfo.processInfo.systemUptime
                    let result = try await performPromptWork { try recognizer.recognize(frame.image, includeQuality: usePhotoChecks) }
                    if !receivedFirstInference {
                        record(String(format: "First face inference %.0fms (%@)", (ProcessInfo.processInfo.systemUptime - inferenceStart) * 1000, result == nil ? "no candidate" : "candidate found"))
                        receivedFirstInference = true
                    }
                    try Task.checkCancellation()
                    guard let result, templates.matches(result.embedding) else {
                        _ = matchGate.observe(frame: frame.id, matched: false)
                        liveness.reset()
                        status = "Looking for your enrolled face…"
                        continue
                    }
                    let faceReady = matchGate.observe(frame: frame.id, matched: true)
                    if usePhotoChecks {
                        let features = try await performPromptWork {
                            let crop = frame.image.cropping(to: result.face.boundingBox)
                            return LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: crop)
                        }
                        let snapshot = liveness.observe(features)
                        guard !snapshot.decision.isDenied else {
                            throw FillError.message(snapshot.decision.denialReason ?? "Photo check failed.")
                        }
                        guard snapshot.decision.isConfirmed else { continue }
                    }
                    guard faceReady else { continue }
                    attemptGate.mark(trigger.requestKey)
                    camera.stop()
                    record("Enrolled face matched on two distinct frames")
                    handedOff = true
                    if useAnimation { NotchOverlayController.shared.faceRecognized() }
                    status = trigger.isBiometric ? "Face recognized. Waiting for the password field to focus…" : "Face recognized. Filling the password field…"
                    let target = try await performPromptWork { try await trigger.passwordTargetAfterRecognition(progress: report) }
                    record("Password field ready (\(target.ownerBundleID))")
                    try Task.checkCancellation()
                    // One attempt includes both stages. Do not immediately rescan
                    // the newly opened password field after a failed input attempt.
                    attemptedField = target.field
                    let verified = try await performPromptWork {
                        var bytes = try SecureCredentialManager.readPassword()
                        defer { bytes.resetBytes(in: 0..<bytes.count) }
                        return try await target.type(bytes, progress: report)
                    }
                    record(verified ? "Input delivery verified" : "Input delivery could not be verified")
                    if verified {
                        // Filling success is already known: let the UI render
                        // immediately while the optional Return is dispatched.
                        if useAnimation { NotchOverlayController.shared.finish(success: true) }
                        if InputActionPolicy.shouldPressReturn(enabledAtStart: useAutomaticReturn, enabledNow: autoSubmit, verified: verified) {
                            try await performPromptWork { try target.pressReturn() }
                            record("Return sent")
                            status = "Password filled and Return pressed."
                        } else {
                            status = "Password filled. Review the request and click \(target.confirmationButton)."
                        }
                    } else {
                        status = "Input could not be verified. Check the password field before continuing."
                    }
                    if !verified && useAnimation { NotchOverlayController.shared.finish(success: false) }
                    filled = true
                    break
                }
                if !filled {
                    recognitionFailed = true
                    status = "Scan timed out. Choose Retry current prompt or hover the island if enabled."
                    if useAnimation { NotchOverlayController.shared.finish(success: false) }
                }
            } catch {
                if !Task.isCancelled {
                    status = error.localizedDescription
                    recognitionFailed = !handedOff
                    record("Stopped: " + error.localizedDescription)
                    if useAnimation { NotchOverlayController.shared.finish(success: false) }
                }
            }
            if generation == currentGeneration {
                camera.stop()
                busy = false
                operation = nil
                if !Task.isCancelled, useAutoRetry, retryBudget.claim(for: trigger.requestKey,
                    enabled: autoRetryOnce, recognitionFailed: recognitionFailed) {
                    scheduleAutomaticRetry(for: trigger, generation: currentGeneration)
                }
            }
        }
    }

    private func scheduleAutomaticRetry(for original: FillTrigger, generation token: Int) {
        retryTask?.cancel()
        retryTask = Task {
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard !Task.isCancelled, token == generation, enabled, autoRetryOnce,
                  dataSessionReady, !busy, !isEditingSavedData, !screenLocked,
                  !sleeping, userSessionActive else { return }
            let allowBiometric = automaticPasswordFallback
            let current = await performPromptWorkSafely(allowBiometric: allowBiometric, original: original)
            guard !Task.isCancelled, token == generation, enabled, autoRetryOnce, !busy,
                  let current, current.requestKey == original.requestKey else { return }
            // Rediscover and reverify the same request. Recognition starts fresh;
            // the retry budget remains spent until manual retry or a new request.
            attemptedField = nil
            attemptGate.reset()
            handleTrigger(current)
        }
    }
    private func performPromptWorkSafely(allowBiometric: Bool, original: FillTrigger) async -> FillTrigger? {
        await Task.detached(priority: .userInitiated) {
            let target = FillTrigger.current(allowBiometric: allowBiometric)
            guard let target, target.verifyAppleSignature(), original.isCurrent(),
                  target.requestKey == original.requestKey,
                  CFEqual(target.element, original.element) else { return nil }
            return target
        }.value
    }

    func removeSavedData() {
        guard canEditOptions else { return }
        isEditingSavedData = true
        defer { isEditingSavedData = false }
        prepareProtectedDataEdit(cancelEnrollment: true)
        let alert = NSAlert()
        alert.messageText = "Remove Faceprint's saved face and password?"
        alert.informativeText = "You can enroll and set up a new session afterward."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard canEditOptions else { return }
        do {
            enabled = false
            UserDefaults.standard.set(false, forKey: "fillingEnabled")
            try SecureCredentialManager.deleteSavedData()
            endRuntimeSession()
            hasPassword = false
            status = "Saved face and password removed."
        } catch { status = error.localizedDescription }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let controller = FillController()
    private let systemSetup = SystemSetup()
    private let updater = UpdateManager()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var subscription: AnyCancellable?
    private var menuBarSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Faceprint", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showWindow), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "faceid", accessibilityDescription: "Faceprint")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Faceprint", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        menuBarSubscription = systemSetup.$showInMenuBar.sink { [weak self] visible in
            self?.statusItem.isVisible = visible
        }
        subscription = controller.$status.sink { [weak self] text in self?.statusItem.button?.toolTip = text }
        systemSetup.canModifySettings = { [weak controller] in controller?.canModifySettings ?? false }
        updater.canModifySettings = { [weak controller] in controller?.canModifySettings ?? false }
        updater.prepareToRestart = { [weak controller] in controller?.endRuntimeSession() }
        let host = NSHostingController(rootView: SetupView(controller: controller, systemSetup: systemSetup, updater: updater))
        window = NSWindow(contentViewController: host)
        window.title = "Faceprint"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Match Glance's native unified titlebar: it positions the real traffic
        // lights inside the header and preserves native window corners/key tint.
        window.toolbar = NSToolbar(identifier: "FaceprintSettingsToolbar")
        window.toolbarStyle = .unified
        let settingsSize = NSSize(width: 500, height: min(620, (NSScreen.main?.visibleFrame.height ?? 760) - 60))
        window.setFrame(NSRect(origin: window.frame.origin, size: settingsSize), display: false)
        window.minSize = settingsSize
        window.maxSize = settingsSize
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        controller.onAuthenticationFinished = { [weak self] in
            // LocalAuthentication may reactivate the previous foreground app as its
            // prompt closes. Restore the visible settings window after that handoff.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.window.isVisible, !self.controller.isEnrollingFace else { return }
                self.showWindow()
            }
        }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showWindow() }
        Task { await systemSetup.requestFirstLaunchPermissions() }
        controller.resumeAutofill()
        Task {
            try? await Task.sleep(for: .seconds(5))
            updater.checkAutomaticallyIfNeeded()
        }
    }

    func windowWillClose(_ notification: Notification) {
        controller.lockSettings()
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }
    func applicationDidBecomeActive(_ notification: Notification) { systemSetup.refresh() }
    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { controller.endRuntimeSession(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.endRuntimeSession() }
}

@main
enum FaceprintMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
