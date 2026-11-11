// Settings layout inspired by jonnyoo/glance (Jonathan Zhou, MIT):
// translucent window, grouped rounded rows, session control and floating tabs.
import AppKit
import SwiftUI
import AVFoundation

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, face, password, camera, recognition, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "General"
        case .face: return "Your Face"
        case .password: return "Password"
        case .camera: return "Camera"
        case .recognition: return "Recognition"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .face: return "faceid"
        case .password: return "key.horizontal"
        case .camera: return "camera"
        case .recognition: return "viewfinder"
        case .about: return "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "Face-assisted filling, on your terms."
        case .face: return "Nine views. One familiar face."
        case .password: return "Your Mac password, encrypted locally."
        case .camera: return "Choose the camera used for recognition."
        case .recognition: return "Control recognition and confirmation."
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

    private var canEdit: Bool { !controller.busy && !controller.enabled }
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
        .onDisappear { controller.passwordDraft = "" }
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
                if controller.sessionUnlocked { controller.lockSession() }
                else { controller.unlockSession() }
            } label: {
                Image(systemName: controller.sessionUnlocked ? "lock.open" : "lock.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain).background(cardFill, in: Circle())
            .disabled(controller.busy && !controller.sessionUnlocked)
            .help(controller.sessionUnlocked ? "Lock session" : "Unlock session")
            .accessibilityLabel(controller.sessionUnlocked ? "Lock session" : "Unlock session")
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
        case .recognition: recognitionPage
        case .about: aboutPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                Toggle("Enable face-assisted filling", isOn: $controller.enabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!controller.enabled && !controller.canEnable)
                    .padding(14)
            }
            if !controller.canEnable && !controller.enabled {
                caption("Unlock your session, enroll your face, and save your Mac password to enable filling.")
            }
            group {
                row("Session", detail: controller.sessionUnlocked ? "Saved data is available for this session." : "Authenticate to use your encrypted saved data.") {
                    Button(controller.sessionUnlocked ? "Lock" : "Unlock") {
                        if controller.sessionUnlocked { controller.lockSession() } else { controller.unlockSession() }
                    }.buttonStyle(.bordered).controlSize(.small)
                        .disabled(controller.busy && !controller.sessionUnlocked)
                }
            }
            group {
                Toggle("Launch at login", isOn: Binding(get: { systemSetup.launchAtLogin }, set: { systemSetup.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.small).padding(14)
            }
            caption(systemSetup.loginStatus)
            if systemSetup.loginNeedsApproval {
                Button("Open Login Items", action: systemSetup.openLoginSettings).buttonStyle(.bordered)
            }
            sectionTitle("DYNAMIC ISLAND")
            group {
                row("Animation", detail: "Recognition and result feedback.") {
                    Picker("Animation", selection: $controller.islandStyle) {
                        Text("Original").tag(UnlockAnimationStyle.original)
                        Text("Minimal").tag(UnlockAnimationStyle.minimal)
                    }.labelsHidden().frame(width: 126).disabled(!canEdit)
                }
            }
            caption("Open Use Password… yourself and focus the empty system password field. Faceprint starts recognition when filling is enabled.")
        }
    }

    @ViewBuilder private var facePage: some View {
        if !controller.sessionUnlocked {
            lockedState("Unlock to view or update your enrolled face.")
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
                        .buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(!canEdit)
                }.frame(maxWidth: .infinity).padding(26)
            }
            if controller.enabled { caption("Turn off filling in General before enrolling again.") }
        }
    }

    @ViewBuilder private var passwordPage: some View {
        if !controller.sessionUnlocked {
            lockedState("Unlock to save or change your Mac login password.")
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
            caption("Use the password for your current Mac account. Saved data is encrypted locally and available only while the session is unlocked.")
            if controller.enabled { caption("Turn off filling in General before changing the saved password.") }
            sectionTitle("SAVED DATA")
            group {
                row("Remove saved data", detail: "Remove both the saved face and password.") {
                    Button("Remove…", action: controller.removeSavedData)
                        .buttonStyle(.bordered).controlSize(.small).disabled(controller.busy)
                }
            }
        }
    }

    private var cameraPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recognition camera").font(.system(size: 13, weight: .medium))
                    Picker("Camera", selection: $controller.cameraID) {
                        Text("System default").tag("")
                        ForEach(devices, id: \.uniqueID) { device in Text(device.localizedName).tag(device.uniqueID) }
                        if !controller.cameraID.isEmpty && !devices.contains(where: { $0.uniqueID == controller.cameraID }) {
                            Text("Selected camera (unavailable)").tag(controller.cameraID)
                        }
                    }.labelsHidden().disabled(!canEdit)
                }.padding(14)
            }
            caption("The camera runs during enrollment and password recognition. Settings does not display or start a camera preview.")
            sectionTitle("PERMISSIONS")
            group {
                row("Camera", detail: systemSetup.cameraStatus) {
                    if systemSetup.cameraGranted { granted }
                    else {
                        Button("Allow") { Task { await systemSetup.requestCamera() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(systemSetup.requestingPermissions)
                    }
                }
                Divider().padding(.horizontal, 14)
                row("Accessibility", detail: systemSetup.accessibilityGranted ? "Allowed for supported password prompts." : "Needed to detect prompts and fill passwords.") {
                    if systemSetup.accessibilityGranted { granted }
                    else { Button("Allow", action: systemSetup.requestAccessibility).buttonStyle(.bordered).controlSize(.small) }
                }
            }
            caption("Permission changes take effect after you return from System Settings. Use the refresh button above to reload connected cameras.")
        }
    }

    private var recognitionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                Toggle("Passive photo checks", isOn: $controller.passivePhotoChecks)
                    .toggleStyle(.switch).controlSize(.small).padding(14).disabled(!canEdit)
            }
            caption("Glance Light checks for obvious screen glare or device borders. No required blink or head turn. Photos or replayed video can still be accepted.")
            group {
                Toggle("Press Return after filling", isOn: $controller.autoSubmit)
                    .toggleStyle(.switch).controlSize(.small).padding(14).disabled(!canEdit)
            }
            caption("Off by default. When enabled, a verified password fill is followed by Return, which can approve a system settings change.")
            sectionTitle("SESSION PROTECTION")
            group {
                row("Automatic lock", detail: "On screen lock, sleep, user-session switch, or 30 minutes without secret use.") {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
            }
            caption("Recognition uses Glance’s ArcFace model with your saved face template. Ordinary webcam matching does not offer Face ID’s replay protection.")
            if controller.enabled { caption("Turn off filling in General to change these options.") }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "Faceprint", withExtension: "icns") ?? URL(fileURLWithPath: "/")) ?? NSApp.applicationIconImage)
                .resizable().scaledToFit().frame(width: 80, height: 80)
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
            Text("Session locked").font(.system(size: 16, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Unlock session", action: controller.unlockSession)
                .buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(controller.busy)
            Text("Locks again on screen lock, sleep, or inactivity.")
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
            control()
        }.padding(14)
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
