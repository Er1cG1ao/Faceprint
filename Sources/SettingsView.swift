// Settings layout inspired by jonnyoo/glance (Jonathan Zhou, MIT):
// translucent window, grouped rounded rows, session control and floating tabs.
import AppKit
import SwiftUI
import AVFoundation

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, face, password, camera, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "General"
        case .face: return "Your Face"
        case .password: return "Password"
        case .camera: return "Camera"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .face: return "faceid"
        case .password: return "key.horizontal"
        case .camera: return "camera"
        case .about: return "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "Face-assisted filling, on your terms."
        case .face: return "Nine views. One familiar face."
        case .password: return "Your Mac password, encrypted locally."
        case .camera: return "Choose the camera used for recognition."
        case .about: return "A familiar face for macOS password prompts."
        }
    }
}

private struct SettingsMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SetupView: View {
    @ObservedObject var controller: FillController
    @ObservedObject var systemSetup: SystemSetup
    @GlanceViewState private var selection: SettingsPage = .general
    @GlanceViewState private var devices = Camera.devices
    @Namespace private var tabAnimation
    @Environment(\.colorScheme) private var colorScheme

    private var canEdit: Bool { controller.canEditOptions }
    private var cardFill: Color { colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.7) }
    private var border: Color { colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08) }

    var body: some View {
        ZStack {
            SettingsMaterial().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selection.title).font(.system(size: 26, weight: .bold))
                        Text(selection.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.bottom, 8)
                    pageBody
                    if selection != .about {
                        HStack(alignment: .top, spacing: 8) {
                            if controller.busy { ProgressView().controlSize(.mini) }
                            Text(controller.status).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.horizontal, 4).padding(.top, 4)
                        if controller.enabled {
                            Text(controller.promptStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                            if !controller.diagnosticTrace.isEmpty {
                                Button("Copy diagnostics") { controller.copyDiagnostics() }
                                    .buttonStyle(.link).font(.system(size: 11))
                                    .help("Copies timing and system-host metadata for the last attempt; no password or face data.")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 66).padding(.bottom, 96)
            }
            .id(selection)
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { tabBar.padding(.bottom, 14) }
        }
        .frame(width: 500, height: min(620, (NSScreen.main?.visibleFrame.height ?? 760) - 60))
        .tint(GlanceTheme.accent)
        .onChange(of: selection) { _, page in
            controller.passwordDraft = ""
            if page == .camera { devices = Camera.devices }
            systemSetup.refresh()
        }
        .onDisappear { controller.lockSettings() }
    }

    private var header: some View {
        HStack {
            Spacer()
            if selection == .camera {
                Button { devices = Camera.devices; systemSetup.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 30, height: 30)
                }.buttonStyle(.plain).background(cardFill, in: Circle())
                    .help("Refresh camera list").accessibilityLabel("Refresh camera list")
            }
            Button {
                if controller.settingsUnlocked { controller.lockSettings() }
                else { controller.unlockSettings() }
            } label: {
                Image(systemName: controller.settingsUnlocked ? "lock.open" : "lock.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain).background(cardFill, in: Circle())
            .disabled(!controller.settingsUnlocked && !controller.canUnlockSettings)
            .help(controller.settingsUnlocked ? "Lock settings" : "Unlock to edit settings")
            .accessibilityLabel(controller.settingsUnlocked ? "Lock settings" : "Unlock to edit settings")
        }
        .padding(.horizontal, 24).frame(height: 52)
        .background(.regularMaterial)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selection = page }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: page.icon).font(.system(size: 15, weight: .medium))
                            .frame(width: 20, height: 20)
                        if selection == page {
                            Text(page.title).font(.system(size: 13, weight: .medium)).fixedSize()
                        }
                    }
                    .padding(.horizontal, selection == page ? 14 : 11).frame(height: 42)
                    .contentShape(Capsule())
                    .background {
                        if selection == page {
                            Capsule().fill(cardFill).overlay(Capsule().strokeBorder(border))
                                .matchedGeometryEffect(id: "selection", in: tabAnimation)
                        }
                    }
                }
                .buttonStyle(.plain).help(page.title).accessibilityLabel(page.title)
                .accessibilityAddTraits(selection == page ? .isSelected : [])
            }
        }
        .padding(6).background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(border))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    @ViewBuilder private var pageBody: some View {
        switch selection {
        case .general: generalPage
        case .face: facePage
        case .password: passwordPage
        case .camera: cameraPage
        case .about: aboutPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                row("Settings", detail: controller.settingsUnlocked
                    ? "Unlocked. You can change settings while autofill stays enabled."
                    : "Unlock to make changes. Enabled autofill keeps working while settings are locked.") {
                    Button(controller.settingsUnlocked ? "Lock" : "Unlock to edit") {
                        if controller.settingsUnlocked { controller.lockSettings() } else { controller.unlockSettings() }
                    }.buttonStyle(.bordered).controlSize(.small)
                        .disabled(!controller.settingsUnlocked && !controller.canUnlockSettings)
                }
            }
            group {
                toggleRow("Enable face-assisted filling", detail: controller.canEnable || controller.enabled
                    ? "Recognize your face and fill supported Mac password prompts. Runs while settings are locked."
                    : "Enroll your face and save your Mac login password before enabling filling.",
                    isOn: Binding(get: { controller.enabled }, set: controller.setEnabled),
                    disabled: !controller.canModifySettings || (!controller.enabled && !controller.canEnable))
                if controller.enabled && !controller.dataSessionReady {
                    rowDivider
                    row("Autofill paused", detail: "Authenticate to open protected data after launch or sleep. Settings stay locked.") {
                        Button("Resume", action: controller.resumeAutofill)
                            .buttonStyle(.bordered).controlSize(.small).disabled(controller.busy)
                    }
                }
            }
            group {
                toggleRow("Launch at login", detail: systemSetup.loginStatus,
                    isOn: Binding(get: { systemSetup.launchAtLogin }, set: { systemSetup.setLaunchAtLogin($0) }))
                if systemSetup.loginNeedsApproval {
                    rowDivider
                    row("Login approval", detail: "Allow Faceprint in macOS Login Items.") {
                        Button("Open Login Items", action: systemSetup.openLoginSettings)
                            .buttonStyle(.bordered).controlSize(.small).disabled(!canEdit)
                    }
                }
            }
            sectionTitle("RECOGNITION")
            recognitionOptions
            sectionTitle("DYNAMIC ISLAND")
            group {
                row("Animation", detail: "Recognition and filling feedback. A new style applies to the next scan.") {
                    Picker("Animation", selection: Binding(get: { controller.islandStyle }, set: controller.setIslandStyle)) {
                        Text("Original").tag(UnlockAnimationStyle.original)
                        Text("Minimal").tag(UnlockAnimationStyle.minimal)
                    }.labelsHidden().frame(width: 126).disabled(!canEdit)
                }
            }
            sectionTitle("PERMISSIONS")
            permissionsGroup
            sectionTitle("SETTINGS & DATA PROTECTION")
            group {
                row("Automatic protection", detail: "Editing locks after 5 minutes. Protected data locks on sleep, screen lock, user switch, or 30 minutes without secret use.") {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
                rowDivider
                row("Local recognition", detail: "Glance’s ArcFace model compares your face on this Mac. Webcam matching does not provide Face ID’s replay protection.") {
                    Image(systemName: "faceid").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recognitionOptions: some View {
        group {
            toggleRow("Passive photo checks", detail: "Glance Light checks for obvious screen glare and device borders. No blink or head turn required. Applies to the next scan; photos or replayed video can still be accepted.",
                isOn: Binding(get: { controller.passivePhotoChecks }, set: controller.setPhotoChecks))
            rowDivider
            toggleRow("Scan Touch ID prompts", detail: "Start recognition at supported Touch ID cards, then select Use Password and fill after a face match. Applies to the next request; off by default.",
                isOn: Binding(get: { controller.automaticPasswordFallback }, set: controller.setAutomaticPasswordFallback))
            rowDivider
            toggleRow("Press Return after filling", detail: "Submit after a verified password fill. This can approve system changes. Off by default; enabling applies to the next attempt.",
                isOn: Binding(get: { controller.autoSubmit }, set: controller.setAutoSubmit))
        }
    }

    private var permissionsGroup: some View {
        group {
            row("Camera", detail: "\(systemSetup.cameraStatus). Used for local face enrollment and recognition.") {
                if systemSetup.cameraGranted { granted }
                else {
                    Button("Allow") { Task { await systemSetup.requestCamera() } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(systemSetup.requestingPermissions || !canEdit)
                }
            }
            rowDivider
            row("Accessibility", detail: systemSetup.accessibilityGranted
                ? "Allowed for detecting native password prompts and filling them. Status refreshes when you return from System Settings."
                : "Allow Faceprint to detect supported prompts and fill their password fields.") {
                if systemSetup.accessibilityGranted { granted }
                else {
                    Button("Allow") { systemSetup.requestAccessibility() }
                        .buttonStyle(.bordered).controlSize(.small).disabled(!canEdit)
                }
            }
        }
    }

    @ViewBuilder private var facePage: some View {
        if !controller.settingsUnlocked {
            lockedState("Unlock settings to enroll or update your face.")
        } else {
            group {
                row("Face encrypted", detail: "Your face template stays on this Mac.") {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
            group {
                VStack(spacing: 16) {
                    Image(systemName: "faceid").font(.system(size: 40, weight: .light)).foregroundStyle(GlanceTheme.accent)
                    Text(controller.hasFace ? "Your face is enrolled" : "Set up your face").font(.system(size: 16, weight: .semibold))
                    Text("Follow the nine-direction capture ring. The camera preview appears only during enrollment.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(controller.hasFace ? "Enroll face again" : "Enroll my face", action: controller.enroll)
                        .buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(!controller.canEnrollFace)
                }.frame(maxWidth: .infinity).padding(26)
            }
            caption("Enrollment temporarily pauses recognition. Your autofill switch stays unchanged and filling resumes when enrollment finishes or is cancelled.")
        }
    }

    @ViewBuilder private var passwordPage: some View {
        if !controller.settingsUnlocked {
            lockedState("Unlock settings to save or change your Mac login password.")
        } else {
            group {
                row(controller.hasPassword ? "Password encrypted" : "No password saved", detail: controller.protectionStatus) {
                    Image(systemName: controller.hasPassword ? "lock.fill" : "key.horizontal").foregroundStyle(.secondary)
                }
            }
            group {
                VStack(alignment: .leading, spacing: 12) {
                    Text(controller.hasPassword ? "Update password" : "Save your Mac password").font(.system(size: 13, weight: .medium))
                    SecureField("Mac login password", text: $controller.passwordDraft)
                        .textFieldStyle(.roundedBorder).disabled(!canEdit)
                    HStack {
                        Spacer()
                        Button("Save password") {
                            do {
                                try controller.savePassword(controller.passwordDraft)
                                controller.passwordDraft = ""
                            } catch { controller.status = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(controller.passwordDraft.isEmpty || !canEdit)
                    }
                }.padding(14)
            }
            caption("Use the password for your current Mac account. Saved data is encrypted locally. Locking settings keeps enabled autofill running.")
            sectionTitle("SAVED DATA")
            group {
                row("Remove saved data", detail: "Remove the saved face and password, and stop autofill.") {
                    Button("Remove…", action: controller.removeSavedData)
                        .buttonStyle(.bordered).controlSize(.small).disabled(!canEdit)
                }
            }
        }
    }

    private var cameraPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                row("Recognition camera", detail: "Used for enrollment and recognition. Changes apply to the next scan.") {
                    Picker("Camera", selection: Binding(get: { controller.cameraID }, set: controller.setCameraID)) {
                        Text("System default").tag("")
                        ForEach(devices, id: \.uniqueID) { device in Text(device.localizedName).tag(device.uniqueID) }
                        if !controller.cameraID.isEmpty && !devices.contains(where: { $0.uniqueID == controller.cameraID }) {
                            Text("Selected camera (unavailable)").tag(controller.cameraID)
                        }
                    }.labelsHidden().frame(width: 180).disabled(!canEdit)
                }
            }
            caption("The camera runs during enrollment and recognition. Camera and Accessibility permissions are in General, below Dynamic Island.")
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "FaceprintBrand", withExtension: "png") ?? URL(fileURLWithPath: "/")) ?? NSApp.applicationIconImage)
                .resizable().scaledToFit().frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 5) {
                Text("Faceprint").font(.system(size: 23, weight: .bold))
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("Local face recognition for supported macOS password prompts.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            group {
                VStack(spacing: 12) {
                    Link("GitHub project", destination: URL(string: "https://github.com/Er1cG1ao/faceprint")!)
                    Link("Built on Glance · Jonathan Zhou · MIT", destination: URL(string: "https://github.com/jonnyoo/glance")!)
                    Link("Licenses & model terms", destination: URL(string: "https://github.com/Er1cG1ao/faceprint/blob/main/THIRD_PARTY_NOTICES.md")!)
                }.font(.system(size: 12)).frame(maxWidth: .infinity).padding(18)
            }
            caption("Faceprint code is MIT licensed. InsightFace pretrained weights retain their separate non-commercial research terms.")
            caption("Apple Silicon · macOS 15+")
        }.frame(maxWidth: .infinity).padding(.top, 12)
    }

    private var granted: some View {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed")
    }

    private func lockedState(_ detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text("Settings locked").font(.system(size: 16, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Unlock to edit", action: controller.unlockSettings)
                .buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(!controller.canUnlockSettings)
            Text("Enabled autofill keeps working while settings are locked.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 280)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(border))
    }

    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control().fixedSize(horizontal: true, vertical: false)
        }.padding(14)
    }

    private var rowDivider: some View { Divider().padding(.horizontal, 14) }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>, disabled: Bool? = nil) -> some View {
        row(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.regular)
                .accessibilityLabel(title).disabled(disabled ?? !canEdit)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 8)
    }
}
