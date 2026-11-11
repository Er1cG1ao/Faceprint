import AppKit
import SwiftUI
import Combine
import AVFoundation
import Carbon

@MainActor
final class FillController: ObservableObject {
    @Published var status = "Choose your camera and click Test camera, then unlock a session."
    @Published var sessionUnlocked = false
    @Published var protectionStatus = "Checking session protection…"
    @Published var promptStatus = "Supports Privacy & Security and native Passwords AutoFill prompts."
    @Published var hasFace = false
    @Published var hasPassword = SecureCredentialManager.hasStoredPassword()
    @Published var busy = false
    @Published var previewing = false
    @Published var passwordDraft = ""
    @Published var testMode = true
    @Published var passivePhotoChecks = false
    @Published var islandStyle = GlanceSettings.shared.animationStyle {
        didSet { GlanceSettings.shared.animationStyle = islandStyle }
    }
    @Published var autoSubmit = UserDefaults.standard.bool(forKey: "autoSubmit") {
        didSet { UserDefaults.standard.set(autoSubmit, forKey: "autoSubmit") }
    }
    @Published var cameraID: String {
        didSet { UserDefaults.standard.set(cameraID, forKey: "cameraID") }
    }
    @Published var enabled = false {
        didSet {
            if !enabled { cancelOperation() }
            else { status = "Waiting for an empty supported system password field." }
        }
    }
    var onAuthenticationFinished: (() -> Void)?
    let camera: Camera
    let enrollment: OnboardingController
    private var template: FaceTemplate?
    private var recognizer: Recognizer?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var attemptedField: AXUIElement?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var authenticationInProgress = false

    var canEnable: Bool { sessionUnlocked && hasFace && (testMode || hasPassword) && !busy }

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.lockSession() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.lockSession() } })
        screenObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.lockSession() } }
    }

    func unlockSession() {
        guard !busy, !authenticationInProgress else { return }
        generation &+= 1
        let currentGeneration = generation
        authenticationInProgress = true
        busy = true
        status = "Authenticate to open your Faceprint session…"
        Task {
            do {
                try await Task.detached {
                    try SecureCredentialManager.unlockSession(reason: "Open your Faceprint session")
                }.value
                guard generation == currentGeneration else {
                    SecureCredentialManager.lockSession()
                    authenticationInProgress = false
                    return
                }
                template = try SecureFaceStore.load()
                hasFace = template != nil
                hasPassword = SecureCredentialManager.hasStoredPassword()
                sessionUnlocked = true
                status = hasFace ? "Session ready. Enable filling when you are ready." : "Choose your camera and enroll your face."
            } catch {
                if generation == currentGeneration { status = error.localizedDescription }
            }
            authenticationInProgress = false
            busy = false
            onAuthenticationFinished?()
        }
    }

    func lockSession() {
        enabled = false
        cancelOperation()
        template = nil
        passwordDraft = ""
        hasFace = false
        sessionUnlocked = false
        SecureCredentialManager.lockSession()
        status = "Session locked. Unlock it from this window to continue."
    }

    func savePassword(_ password: String) throws {
        guard sessionUnlocked, !busy else { throw FillError.message("Unlock your session first.") }
        guard !password.contains(where: { $0.isNewline || $0 == "\t" }) else {
            throw FillError.message("The password contains an unsupported control character.")
        }
        var data = Data(password.utf8)
        defer { data.resetBytes(in: 0..<data.count) }
        try SecureCredentialManager.savePassword(data)
        hasPassword = true
        status = "Password encrypted and saved."
    }

    func retry() {
        guard enabled, !busy else { return }
        attemptedField = nil
        status = "Focus the empty system password field."
    }

    private func cancelOperation() {
        generation &+= 1
        operation?.cancel()
        operation = nil
        camera.stop()
        enrollment.dismiss()
        NotchOverlayController.shared.dismissImmediately()
        previewing = false
        busy = false
    }

    func testCamera() {
        guard !busy else { return }
        enabled = false
        busy = true
        generation &+= 1
        let currentGeneration = generation
        let deviceID = cameraID
        status = "Requesting camera access…"
        operation = Task {
            do {
                try await camera.start(deviceID: deviceID)
                try Task.checkCancellation()
                previewing = true
                status = "Camera preview is running. Click Stop camera when ready."
                let deadline = Date().addingTimeInterval(30)
                while Date() < deadline {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                status = "Camera test finished. Unlock a session to enroll your face."
            } catch {
                if !Task.isCancelled { status = error.localizedDescription }
            }
            if generation == currentGeneration {
                camera.stop()
                previewing = false
                busy = false
                operation = nil
            }
        }
    }

    func stopCameraPreview() {
        cancelOperation()
        status = "Camera test stopped. Unlock a session to enroll your face."
    }

    func previewIsland() {
        guard !busy else { return }
        busy = true
        generation &+= 1
        let currentGeneration = generation
        status = "Previewing Glance’s Dynamic Island animations…"
        NotchOverlayController.shared.presentPreview()
        operation = Task {
            do {
                try await Task.sleep(for: .seconds(6))
                try Task.checkCancellation()
                NotchOverlayController.shared.finish(success: true)
                try await Task.sleep(for: .seconds(2.6))
                try Task.checkCancellation()
                status = "Dynamic Island preview finished."
            } catch {}
            if generation == currentGeneration {
                busy = false
                operation = nil
            }
        }
    }

    private func getRecognizer() async throws -> Recognizer {
        if let recognizer { return recognizer }
        let loaded = try await Task.detached { try Recognizer() }.value
        recognizer = loaded
        return loaded
    }

    func enroll() {
        guard sessionUnlocked, !busy else { return }
        enabled = false
        busy = true
        generation &+= 1
        let currentGeneration = generation
        status = "Follow the nine-direction guide in the Dynamic Island."
        let deviceID = cameraID
        operation = Task {
            do {
                let recognizer = try await getRecognizer()
                try Task.checkCancellation()
                let saved = try await enrollment.capture(using: recognizer, deviceID: deviceID)
                try Task.checkCancellation()
                try SecureFaceStore.save(saved)
                template = saved
                hasFace = true
                status = "All nine views enrolled. Face recognition is ready."
            } catch {
                if !Task.isCancelled { status = error.localizedDescription }
            }
            if generation == currentGeneration {
                camera.stop()
                enrollment.dismiss()
                busy = false
                operation = nil
            }
        }
    }

    private func poll() {
        if sessionUnlocked, let activity = SecureCredentialManager.lastActivityAt,
           Date().timeIntervalSince(activity) >= 30 * 60 {
            lockSession()
            return
        }
        guard enabled, sessionUnlocked, !busy, let template else { return }
        guard AXIsProcessTrusted() else {
            status = "Grant Faceprint Accessibility access, then enable filling again."
            enabled = false
            return
        }
        guard let target = PromptTarget.current() else {
            if let diagnostic = PromptTarget.diagnosticSummary() { promptStatus = diagnostic }
            return
        }
        promptStatus = "Recognized \(target.description) prompt."
        if let attemptedField, CFEqual(attemptedField, target.field) { return }
        guard target.verifyAppleSignature() else {
            status = "The focused field's Apple signature could not be verified."
            return
        }
        attemptedField = target.field
        busy = true
        generation &+= 1
        let currentGeneration = generation
        let useTestMode = testMode
        let usePhotoChecks = passivePhotoChecks
        let useAutomaticReturn = autoSubmit
        let deviceID = cameraID
        status = "Looking for your face…"
        NotchOverlayController.shared.present(onRetry: { [weak self] in self?.retry() })
        operation = Task {
            do {
                let recognizer = try await getRecognizer()
                try Task.checkCancellation()
                guard target.isCurrent(requireEmpty: true) else { throw CancellationError() }
                try await camera.start(deviceID: deviceID)
                try Task.checkCancellation()
                let liveness = LivenessAnalyzer()
                liveness.modeProvider = { .light }
                var consecutiveMatches = 0
                var lastFrame: UInt64?
                var matchedSince: Date?
                let deadline = Date().addingTimeInterval(12)
                var filled = false
                while Date() < deadline {
                    try Task.checkCancellation()
                    guard target.isCurrent(requireEmpty: true) else {
                        throw FillError.message("Focus changed. Return to the empty field and choose Retry from the menu.")
                    }
                    guard let frame = camera.latestFrame(), frame.id != lastFrame else {
                        try await Task.sleep(nanoseconds: 30_000_000)
                        continue
                    }
                    lastFrame = frame.id
                    let result = try await Task.detached { try recognizer.recognize(frame.image) }.value
                    try Task.checkCancellation()
                    guard let result, template.matches(result.embedding) else {
                        consecutiveMatches = 0
                        matchedSince = nil
                        liveness.reset()
                        status = "Looking for your enrolled face…"
                        continue
                    }
                    consecutiveMatches += 1
                    if matchedSince == nil { matchedSince = Date() }
                    if usePhotoChecks {
                        let crop = frame.image.cropping(to: result.face.boundingBox)
                        let features = LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: crop)
                        let snapshot = liveness.observe(features)
                        guard !snapshot.decision.isDenied else {
                            throw FillError.message(snapshot.decision.denialReason ?? "Photo check failed.")
                        }
                        guard snapshot.decision.isConfirmed else { continue }
                    }
                    status = "Face recognized. Filling the password field…"
                    guard consecutiveMatches >= 3,
                          Date().timeIntervalSince(matchedSince ?? Date()) >= 0.25 else { continue }
                    var bytes = useTestMode ? Data("x".utf8) : try SecureCredentialManager.readPassword()
                    defer { bytes.resetBytes(in: 0..<bytes.count) }
                    let verified = try await target.type(bytes)
                    if verified {
                        if InputActionPolicy.shouldPressReturn(enabled: useAutomaticReturn, testMode: useTestMode, verified: verified) {
                            try target.pressReturn()
                            status = "Password filled and Return pressed."
                        } else {
                            status = useTestMode
                                ? "Test character appeared in the field. Click Cancel."
                                : "Password filled. Review the request and click \(target.confirmationButton)."
                        }
                    } else {
                        status = "Input could not be verified. Check the password field before continuing."
                    }
                    NotchOverlayController.shared.finish(success: verified)
                    filled = true
                    break
                }
                if !filled {
                    status = "Scan timed out. Hover the Dynamic Island to retry, then focus the empty field."
                    NotchOverlayController.shared.finish(success: false)
                }
            } catch {
                if !Task.isCancelled {
                    status = error.localizedDescription
                    NotchOverlayController.shared.finish(success: false)
                }
            }
            if generation == currentGeneration {
                camera.stop()
                busy = false
                operation = nil
            }
        }
    }

    func removeSavedData() {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Remove Faceprint's saved face and password?"
        alert.informativeText = "You can enroll and set up a new session afterward."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            enabled = false
            try SecureCredentialManager.deleteSavedData()
            lockSession()
            hasPassword = false
            status = "Saved face and password removed."
        } catch { status = error.localizedDescription }
    }
}

struct SetupView: View {
    @ObservedObject var controller: FillController
    @ObservedObject var systemSetup: SystemSetup
    private let devices = Camera.devices

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text("Faceprint").font(.title2.bold())
                        Text("0.1.1 Beta 2").font(.caption).foregroundStyle(.secondary)
                        Text("Face-assisted filling for system prompts and AutoFill").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(controller.status).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button(controller.sessionUnlocked ? "Session unlocked" : "Unlock session", action: controller.unlockSession)
                        .disabled(controller.sessionUnlocked || controller.busy)
                    Button("Lock session", action: controller.lockSession).disabled(!controller.sessionUnlocked)
                    Spacer()
                    Button("Accessibility access", action: systemSetup.requestAccessibility)
                }
                Text("Unlock session authorizes access to your encrypted face and password for this session. It locks again on screen lock, sleep, or 30 minutes without use.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(controller.protectionStatus).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GroupBox("Startup & Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch Faceprint at login", isOn: Binding(
                            get: { systemSetup.launchAtLogin },
                            set: { systemSetup.setLaunchAtLogin($0) }
                        ))
                        Text(systemSetup.loginStatus).font(.caption).foregroundStyle(.secondary)
                        if systemSetup.loginNeedsApproval {
                            Button("Open Login Items", action: systemSetup.openLoginSettings)
                        }
                        Divider()
                        HStack {
                            Label(systemSetup.cameraStatus, systemImage: systemSetup.cameraGranted ? "checkmark.circle.fill" : "camera")
                                .font(.caption)
                            Spacer()
                            if !systemSetup.cameraGranted {
                                Button("Allow Camera") { Task { await systemSetup.requestCamera() } }
                                    .disabled(systemSetup.requestingPermissions)
                            }
                        }
                        HStack {
                            Label(systemSetup.accessibilityGranted ? "Accessibility allowed" : "Accessibility access needed",
                                  systemImage: systemSetup.accessibilityGranted ? "checkmark.circle.fill" : "accessibility")
                                .font(.caption)
                            Spacer()
                            if !systemSetup.accessibilityGranted {
                                Button("Allow Accessibility", action: systemSetup.requestAccessibility)
                            }
                        }
                        Text("Camera recognizes your face locally. Accessibility detects supported password prompts and types into them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("Camera", selection: $controller.cameraID) {
                    Text("System default").tag("")
                    ForEach(devices, id: \.uniqueID) { device in Text(device.localizedName).tag(device.uniqueID) }
                }.disabled(controller.busy)
                HStack {
                    Button(controller.previewing ? "Stop camera" : "Test camera") {
                        if controller.previewing { controller.stopCameraPreview() }
                        else { controller.testCamera() }
                    }.disabled(controller.busy && !controller.previewing)
                    Button("Preview Dynamic Island", action: controller.previewIsland).disabled(controller.busy)
                }
                CameraPreviewView(camera: controller.camera)
                    .frame(height: 190).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button(controller.hasFace ? "Enroll face again" : "Enroll my face", action: controller.enroll)
                        .disabled(!controller.sessionUnlocked || controller.busy)
                    Text(controller.hasFace ? "Face saved" : "Nine guided views, with Glance’s capture ring.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if controller.busy { ProgressView().controlSize(.small) }
                }
                Divider()
                HStack {
                    SecureField("Your Mac login password", text: $controller.passwordDraft)
                        .disabled(!controller.sessionUnlocked || controller.busy)
                    Button("Save password") {
                        do {
                            try controller.savePassword(controller.passwordDraft)
                            controller.passwordDraft = ""
                        } catch { controller.status = error.localizedDescription }
                    }.disabled(controller.passwordDraft.isEmpty || !controller.sessionUnlocked || controller.busy)
                }
                Text(controller.hasPassword ? "Password encrypted and saved." : "You can try test mode before saving a password.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Dynamic Island", selection: $controller.islandStyle) {
                    Text("Original").tag(UnlockAnimationStyle.original)
                    Text("Minimal").tag(UnlockAnimationStyle.minimal)
                }.disabled(controller.busy || controller.enabled)
                Toggle("Test mode — fill a single x after recognizing me", isOn: $controller.testMode)
                    .disabled(controller.busy || controller.enabled)
                Toggle("Passive photo checks (Glance Light)", isOn: $controller.passivePhotoChecks)
                    .disabled(controller.busy || controller.enabled)
                Toggle("Press Return automatically after filling", isOn: $controller.autoSubmit)
                    .disabled(controller.busy || controller.enabled)
                Text("Automatic Return runs after a verified password fill. Test mode always leaves confirmation to you.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Enable face-assisted filling", isOn: $controller.enabled)
                    .disabled(!controller.enabled && !controller.canEnable)
                Text(controller.promptStatus).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(controller.autoSubmit
                     ? "Open the password entry field yourself. After a verified fill, Faceprint presses Return to confirm."
                     : "Click Use Password… yourself and focus the empty system password field. After filling, review the request and click Modify Settings or OK yourself.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Face matching runs automatically, with optional passive photo checks. Sessions lock after 30 minutes without secret use, on screen lock or sleep. With photo checks off, photos or video can also be accepted.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Remove saved data…", action: controller.removeSavedData).disabled(controller.busy)
                    Spacer()
                    Link("Built on Glance · Jonathan Zhou · MIT", destination: URL(string: "https://github.com/jonnyoo/glance")!)
                        .font(.caption2)
                }
            }.padding(22)
        }.frame(width: 560, height: min(800, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = FillController()
    private let systemSetup = SystemSetup()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Faceprint", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "faceid", accessibilityDescription: "Faceprint")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Faceprint…", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Retry current prompt", action: #selector(retry), keyEquivalent: "")
        menu.addItem(withTitle: "Lock session", action: #selector(lock), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Faceprint", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        subscription = controller.$status.sink { [weak self] text in self?.statusItem.button?.toolTip = text }
        let host = NSHostingController(rootView: SetupView(controller: controller, systemSetup: systemSetup))
        window = NSWindow(contentViewController: host)
        window.title = "Faceprint"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        controller.onAuthenticationFinished = { [weak self] in
            // LocalAuthentication may reactivate the previous foreground app as its
            // prompt closes. Restore the visible settings window after that handoff.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.window.isVisible, !self.controller.busy else { return }
                self.showWindow()
            }
        }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showWindow() }
        Task { await systemSetup.requestFirstLaunchPermissions() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { systemSetup.refresh() }
    @objc func showWindow() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func retry() { controller.retry() }
    @objc func lock() { controller.lockSession() }
    @objc func quit() { controller.lockSession(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.lockSession() }
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
