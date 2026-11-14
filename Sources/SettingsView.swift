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
    @ObservedObject var updater: UpdateManager
    @GlanceViewState private var selection: SettingsPage = .general
    @GlanceViewState private var devices = Camera.devices
    @GlanceViewState private var passwordError: String?
    @GlanceViewState private var identityToDelete: FaceIdentity?
    @GlanceViewState private var tabFrames: [SettingsPage: CGRect] = [:]
    @Environment(\.colorScheme) private var colorScheme

    private var canEdit: Bool { controller.canEditOptions }
    private var cardFill: Color { colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.75) }
    private var border: Color { colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.15) }

    var body: some View {
        ZStack {
            SettingsMaterial().ignoresSafeArea()
            if !controller.settingsUnlocked {
                lockedState
                    .padding(.bottom, 72)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        pageBody

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 84)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                ProgressiveHeaderBlur(height: 80).accessibilityHidden(true)
                header
            }
        }
        .overlay(alignment: .bottom) { tabBar.padding(.bottom, 14) }
        // Include overlay chrome in the full-window coordinate space too;
        // otherwise the toolbar safe inset shifts the Session capsule down.
        .ignoresSafeArea()
        .tint(GlanceTheme.accent)
        .onChange(of: selection) { _, page in
            controller.passwordDraft = ""
            if page == .camera { devices = Camera.devices }
            systemSetup.refresh()
        }
        .onDisappear { selection = .general; controller.lockSettings() }
        .confirmationDialog("Delete this enrolled face?", isPresented: Binding(
            get: { identityToDelete != nil }, set: { if !$0 { identityToDelete = nil } }
        ), titleVisibility: .visible) {
            if let identity = identityToDelete {
                Button("Delete \(identity.name)", role: .destructive) {
                    controller.deleteIdentity(identity.id); identityToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { identityToDelete = nil }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            if selection == .camera && controller.settingsUnlocked {
                Button { devices = Camera.devices; systemSetup.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 30, height: 30)
                }.buttonStyle(.plain).background(cardFill, in: Circle())
                    .help("Refresh camera list").accessibilityLabel("Refresh camera list")
            }
            Button {
                if controller.settingsUnlocked { controller.lockSettings() }
                else { controller.unlockSettings() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: controller.settingsUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 12))
                        .contentTransition(.symbolEffect(.replace))
                    Text(controller.settingsUnlocked ? "Session unlocked" : "Session locked")
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(cardFill, in: Capsule())
                .overlay(Capsule().strokeBorder(border))
            }
            .buttonStyle(.plain)
            .disabled(!controller.settingsUnlocked && !controller.canUnlockSettings)
            .help(controller.settingsUnlocked ? "Lock session" : "Unlock session")
            .accessibilityLabel(controller.settingsUnlocked ? "Lock session" : "Unlock session")
            .animation(.easeInOut(duration: 0.28), value: controller.settingsUnlocked)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private var tabBar: some View {
        ZStack(alignment: .topLeading) {
            if let frame = tabFrames[selection] {
                Capsule().fill(cardFill).overlay(Capsule().strokeBorder(border))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.opacity)
            }
            HStack(spacing: 0) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selection = page }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: page.icon).font(.system(size: 15, weight: .medium))
                                .frame(width: 19, height: 19)
                            if selection == page {
                                Text(page.title).font(.system(size: 13, weight: .medium)).fixedSize()
                                    .transition(.modifier(active: SettingsTabReveal(progress: 0),
                                                          identity: SettingsTabReveal(progress: 1)))
                            }
                        }
                        .padding(.horizontal, selection == page ? 14 : 11).frame(height: 42)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).help(page.title).accessibilityLabel(page.title)
                    .accessibilityAddTraits(selection == page ? .isSelected : [])
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: SettingsTabFrames.self,
                            value: [page: proxy.frame(in: .named("FaceprintTabs"))])
                    })
                }
            }
        }
        .coordinateSpace(name: "FaceprintTabs")
        .padding(.horizontal, 6).frame(height: 54)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(border))
        .onPreferenceChange(SettingsTabFrames.self) { frames in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tabFrames = frames }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            if !systemSetup.cameraGranted || !systemSetup.accessibilityGranted {
                sectionTitle("Permissions")
                permissionsGroup
            }
            group {
                toggleRow("Enable face-assisted filling", detail: "",
                    isOn: Binding(get: { controller.enabled }, set: controller.setEnabled),
                    disabled: !controller.canModifySettings || (!controller.enabled && !controller.canEnable))
                rowDivider
                toggleRow("Launch at login", detail: "",
                    isOn: Binding(get: { systemSetup.launchAtLogin }, set: { systemSetup.setLaunchAtLogin($0) }))
                rowDivider
                toggleRow("Show in menu bar", detail: "",
                    isOn: Binding(get: { systemSetup.showInMenuBar }, set: systemSetup.setShowInMenuBar))
                if systemSetup.loginNeedsApproval {
                    rowDivider
                    row("Login approval", detail: "Allow Faceprint in macOS Login Items.") {
                        Button("Open Login Items", action: systemSetup.openLoginSettings)
                            .buttonStyle(.bordered).controlSize(.small).disabled(!canEdit)
                    }
                }
            }
            sectionTitle("Behavior")
            recognitionOptions
            sectionTitle("Animation")
            animationOptions
        }
    }

    private var recognitionOptions: some View {
        group {
            toggleRow("Retry on notch hover", detail: "",
                isOn: Binding(get: { controller.retryOnHover }, set: controller.setRetryOnHover))
            rowDivider
            toggleRow("Auto retry once after failure", detail: "",
                isOn: Binding(get: { controller.autoRetryOnce }, set: controller.setAutoRetryOnce))
            rowDivider
            toggleRow("Passive photo checks", detail: "Checks for obvious photos or screens. No blink or head turn required.",
                isOn: Binding(get: { controller.passivePhotoChecks }, set: controller.setPhotoChecks))
            rowDivider
            toggleRow("Scan Touch ID prompts", detail: "Recognize your face at Touch ID prompts, then switch to password filling.",
                isOn: Binding(get: { controller.automaticPasswordFallback }, set: controller.setAutomaticPasswordFallback))
            rowDivider
            toggleRow("Press Return after filling", detail: "Press Return after filling. Can approve system changes.",
                isOn: Binding(get: { controller.autoSubmit }, set: controller.setAutoSubmit))
        }
    }

    private var animationOptions: some View {
        group {
            toggleRow("Show animation", detail: "",
                isOn: Binding(get: { controller.showAnimation }, set: controller.setShowAnimation))
            rowDivider
            HStack(alignment: .top, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Style").font(.system(size: 13))
                    Text("The animation that appears when filling a password")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                animationTile(.minimal, title: "Minimal")
                animationTile(.original, title: "Original")
            }.padding(.horizontal, 14).padding(.vertical, 14)
                .disabled(!canEdit || !controller.showAnimation)
                .opacity(controller.showAnimation ? 1 : 0.4)
        }
    }

    private func animationTile(_ style: UnlockAnimationStyle, title: String) -> some View {
        let selected = controller.islandStyle == style
        return Button { controller.selectAnimation(style) } label: {
            VStack(spacing: 8) {
                ZStack {
                    cardFill
                    if selected { GlanceTheme.accent.opacity(0.12) }
                    if style == .minimal {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            Spacer(minLength: 6)
                            animationStill.frame(width: 18, height: 18)
                        }.padding(.horizontal, 10).frame(height: 28)
                            .background(.black, in: Capsule()).padding(.horizontal, 12)
                    } else {
                        animationStill.padding(10).frame(width: 50, height: 50)
                            .background(.black, in: RoundedRectangle(cornerRadius: 17))
                    }
                }.frame(width: 112, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .shadow(color: .black.opacity(0.15), radius: 4)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(border))
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 19)
                                .strokeBorder(GlanceTheme.accent, lineWidth: 3.5).padding(-6)
                        }
                    }
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? .primary : .secondary)
            }
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var animationStill: some View {
        Group {
            if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { Image(systemName: "faceid").foregroundStyle(GlanceTheme.accent) }
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

    private var facePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            group {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Face encrypted").font(.system(size: 13))
                        Spacer()
                        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Text("Enroll separate identities for different people, accessories (e.g. glasses), facial expressions, or new lighting environments. This improves recognition quality.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 14).padding(.vertical, 12)
            }
            HStack {
                sectionTitle("Identities")
                Spacer()
                Button {
                    controller.enroll()
                } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(!controller.canEnrollFace).help("Enroll another face")
                    .padding(.trailing, 10).padding(.top, 8)
            }
            ForEach(controller.identities) { identity in
                identityCard(identity)
            }
            if controller.identities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "faceid").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Face enrollment").font(.system(size: 13))
                    Button("Enroll my face") { controller.enroll() }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        .disabled(!controller.canEnrollFace)
                }.frame(maxWidth: .infinity, minHeight: 240)
            } else if !controller.hasFace {
                caption("No identities are enabled. Switch one on to use face-assisted filling.")
            }
        }
    }

    private func identityCard(_ identity: FaceIdentity) -> some View {
        group {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(identity.name).font(.system(size: 13)).lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(cardFill, in: Capsule()).overlay(Capsule().strokeBorder(border))
                    Spacer(minLength: 8)
                    Toggle("Enable \(identity.name)", isOn: Binding(
                        get: { controller.identities.first { $0.id == identity.id }?.isEnabled ?? false },
                        set: { controller.setIdentityEnabled(identity.id, enabled: $0) }
                    )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!canEdit || controller.isEnrollingFace)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(qualityCaption(identity.template)).font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        qualityTicks(identity.template)
                        Spacer(minLength: 12)
                        Button("Recapture") { controller.enroll(identityID: identity.id) }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                            .disabled(!controller.canEnrollFace)
                        Button { identityToDelete = identity } label: {
                            Image(systemName: "trash").frame(width: 18, height: 18)
                        }.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                            .disabled(!canEdit || controller.isEnrollingFace).help("Delete \(identity.name)")
                    }
                }.opacity(identity.isEnabled ? 1 : 0.45)
            }.padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    private func qualityCaption(_ template: FaceTemplate) -> String {
        let ratings = template.qualities?.compactMap { $0 } ?? []
        guard !ratings.isEmpty else { return "Capture quality • not recorded" }
        let percent = Int((Double(ratings.filter { $0 >= 0.4 }.count) / Double(ratings.count) * 100).rounded())
        return "Capture quality • \(percent)%"
    }

    private func qualityTicks(_ template: FaceTemplate) -> some View {
        HStack(spacing: 5.5) {
            ForEach(template.samples.indices, id: \.self) { index in
                Capsule().fill(qualityColor(template.qualities.flatMap { index < $0.count ? $0[index] : nil }))
                    .frame(maxWidth: 3.5)
            }
        }.frame(width: min(250, max(0, CGFloat(template.samples.count) * 9 - 5.5)), height: 26)
            .accessibilityLabel("Capture quality for \(template.samples.count) samples")
    }

    private func qualityColor(_ value: Float?) -> Color {
        guard let value else { return .secondary.opacity(0.4) }
        if value < 0.4 { return Color(red: 1, green: 0.33, blue: 0.33) }
        if value < 0.5 { return Color(red: 1, green: 0.75, blue: 0.33) }
        return Color(red: 0.52, green: 1, blue: 0.47)
    }

    @ViewBuilder private var passwordPage: some View {
        if !controller.settingsUnlocked {
            lockedState
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
                                passwordError = nil
                            } catch { passwordError = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(controller.passwordDraft.isEmpty || !canEdit)
                    }
                    if let passwordError {
                        Text(passwordError).font(.system(size: 11)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(14)
            }
            sectionTitle("SAVED DATA")
            group {
                row("Remove saved data", detail: "Remove the saved face and password, and stop autofill.") {
                    Button("Remove…", action: controller.removeSavedData)
                        .buttonStyle(.bordered).controlSize(.small).disabled(!canEdit)
                }
            }
        }
    }

    private var cameraLabel: String {
        if controller.cameraID.isEmpty { return "System default" }
        return devices.first { $0.uniqueID == controller.cameraID }?.localizedName ?? "Camera unavailable"
    }

    private var cameraPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            group {
                row("Recognition camera", detail: "Used for enrollment and recognition. Changes apply to the next scan.") {
                    Menu {
                        Button("System default") { controller.setCameraID("") }
                        ForEach(devices, id: \.uniqueID) { device in
                            Button(device.localizedName) { controller.setCameraID(device.uniqueID) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(cameraLabel).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }.font(.system(size: 13)).foregroundStyle(.primary)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(cardFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(border))
                            .contentShape(Capsule())
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .tint(.primary).fixedSize().disabled(!canEdit)
                        .accessibilityLabel("Recognition camera: \(cameraLabel)")
                }
            }
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
            group {
                row("Check for Updates", detail: updater.status) {
                    Button(updater.checking ? "Checking…" : "Check", action: updater.check)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                        .disabled(updater.checking || updater.installing)
                }
                rowDivider
                toggleRow("Automatically check for updates", detail: "",
                    isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks))
                if let update = updater.available {
                    rowDivider
                    row("Faceprint \(update.version)", detail: updater.installing ? "Downloading and verifying the update…" : "Install the GitHub release and restart Faceprint.") {
                        Button(updater.installing ? "Installing…" : "Install and Restart", action: updater.install)
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                            .disabled(updater.installing || !canEdit)
                    }
                    if updater.installing { ProgressView(value: updater.progress).padding(.horizontal, 14).padding(.bottom, 12) }
                }
            }
            group {
                VStack(spacing: 12) {
                    Link("GitHub project", destination: URL(string: "https://github.com/Er1cG1ao/faceprint")!)
                    Link("Built on Glance · Jonathan Zhou · MIT", destination: URL(string: "https://github.com/jonnyoo/glance")!)
                    Link("Licenses & model terms", destination: URL(string: "https://github.com/Er1cG1ao/faceprint/blob/main/THIRD_PARTY_NOTICES.md")!)
                }.font(.system(size: 12)).frame(maxWidth: .infinity).padding(18)
            }
        }.frame(maxWidth: .infinity).padding(.top, 12)
    }

    private var granted: some View {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed")
    }

    private var lockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text("Session locked").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                .padding(.top, 4)
            Button("Unlock session", action: controller.unlockSettings)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.large).font(.system(size: 13, weight: .semibold))
                .disabled(!controller.canUnlockSettings)
            if controller.needsVaultMigration {
                Text("Unlock once to upgrade saved data. Autofill will then start automatically.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 260)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control().fixedSize(horizontal: true, vertical: false)
        }.padding(.horizontal, 14).padding(.vertical, detail.isEmpty ? 0 : 12)
            .frame(minHeight: 44)
    }

    private var rowDivider: some View { Divider().padding(.horizontal, 14) }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>, disabled: Bool? = nil) -> some View {
        row(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title).disabled(disabled ?? !canEdit)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 8)
    }
}

// Adapted from Glance SettingsTabBar (Jonathan Zhou, MIT; LICENSE-Glance.txt).
private struct SettingsTabFrames: PreferenceKey {
    static var defaultValue: [SettingsPage: CGRect] = [:]
    static func reduce(value: inout [SettingsPage: CGRect], nextValue: () -> [SettingsPage: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SettingsTabReveal: ViewModifier {
    var progress: CGFloat
    func body(content: Content) -> some View {
        content.opacity(progress).blur(radius: (1 - progress) * 4)
            .offset(x: (1 - progress) * -10)
    }
}
