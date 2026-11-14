import AppKit
import AVFoundation
import Combine
import ServiceManagement

@MainActor
final class SystemSetup: ObservableObject {
    @Published private(set) var launchAtLogin = false
    @Published private(set) var showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginStatus = ""
    @Published private(set) var cameraStatus = ""
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var cameraGranted = false
    @Published private(set) var requestingPermissions = false

    var canModifySettings: () -> Bool = { false }

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
        switch status {
        case .enabled: loginStatus = "Faceprint opens when you log in. Autofill can run while settings stay locked."
        case .requiresApproval: loginStatus = "Allow Faceprint in System Settings → General → Login Items."
        case .notRegistered: loginStatus = "Off. Faceprint will not open automatically."
        case .notFound: loginStatus = "Install Faceprint in Applications before enabling launch at login."
        @unknown default: loginStatus = "Login item status is unavailable."
        }
        accessibilityGranted = AXIsProcessTrusted()
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        cameraGranted = camera == .authorized
        switch camera {
        case .authorized: cameraStatus = "Camera allowed"
        case .notDetermined: cameraStatus = "Camera access needed"
        case .denied, .restricted: cameraStatus = "Camera blocked — allow Faceprint in System Settings"
        @unknown default: cameraStatus = "Camera permission unavailable"
        }
    }

    func setShowInMenuBar(_ visible: Bool) {
        guard canModifySettings() else { return }
        showInMenuBar = visible
        UserDefaults.standard.set(visible, forKey: "showInMenuBar")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canModifySettings() else { return }
        do {
            if enabled {
                let path = Bundle.main.bundleURL.standardizedFileURL.path
                let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
                guard path.hasPrefix("/Applications/") || path.hasPrefix(userApps) else {
                    throw FillError.message("Move Faceprint to Applications before enabling launch at login.")
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            loginStatus = "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    func requestAccessibility(initialSetup: Bool = false) {
        guard initialSetup || canModifySettings() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func requestCamera(initialSetup: Bool = false) async {
        guard (initialSetup || canModifySettings()), !requestingPermissions else { return }
        requestingPermissions = true
        defer { requestingPermissions = false; refresh() }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: openPrivacySettings("Camera")
        default: break
        }
    }

    /// Run after the setup window is shown. Each macOS permission remains user-controlled.
    func requestFirstLaunchPermissions() async {
        guard !UserDefaults.standard.bool(forKey: "permissionOnboardingShown") else { return }
        UserDefaults.standard.set(true, forKey: "permissionOnboardingShown")
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            await requestCamera(initialSetup: true)
        }
        if !AXIsProcessTrusted() { requestAccessibility(initialSetup: true) }
        refresh()
    }

    func openLoginSettings() {
        guard canModifySettings() else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    func openPrivacySettings(_ pane: String) {
        guard ["Camera", "Accessibility"].contains(pane),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
