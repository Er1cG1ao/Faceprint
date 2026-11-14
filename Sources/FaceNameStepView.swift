// Adapted from Glance NameStepView (Jonathan Zhou, MIT; LICENSE-Glance.txt).
import SwiftUI

struct FaceNameStepView: View {
    @Bindable var controller: OnboardingController
    @Environment(\.notchPanelStyle) private var style
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name this face").font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary).padding(.leading, 4)
            Text("Used to tell enrolled faces apart when more than one person is set up on this Mac.")
                .font(GlanceTheme.Font.passwordCaption).foregroundStyle(GlanceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
            Spacer(minLength: 2)
            TextField("Enter a name…", text: $controller.faceName)
                .textFieldStyle(.plain).font(GlanceTheme.Font.button).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 38)
                .background(GlanceTheme.surface, in: Capsule()).focused($nameFocused)
                .onSubmit { controller.saveName() }
            HStack(spacing: 10) {
                nameButton("Back", primary: false) { controller.back() }
                nameButton("Save", primary: true) { controller.saveName() }
                    .disabled(controller.faceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, OnboardingMetrics.titleTopInset(for: style))
        .padding(.leading, OnboardingMetrics.contentLeadingInset(for: style))
        .padding(.trailing, OnboardingMetrics.contentTrailingInset(for: style))
        .padding(.bottom, OnboardingMetrics.contentBottomInset(for: style))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
        .task {
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            nameFocused = true
        }
    }

    private func nameButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(GlanceTheme.Font.button).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(primary ? GlanceTheme.accent : GlanceTheme.surface, in: Capsule())
        }.buttonStyle(.plain)
    }
}
