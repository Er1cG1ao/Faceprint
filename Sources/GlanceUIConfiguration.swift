import SwiftUI

// Select the property-wrapper type when building with SDKs that also export
// a State macro. The upstream view's state and animations are unchanged.
typealias GlanceViewState<Value> = SwiftUI.State<Value>

enum UnlockAnimationStyle: String {
    case none, minimal, original
}

@MainActor
final class GlanceSettings {
    static let shared = GlanceSettings()
    let faceDetectionSeconds = 12
    let retryOnHover = true
    let hapticFeedbackEnabled = true
    var animationStyle: UnlockAnimationStyle {
        didSet { UserDefaults.standard.set(animationStyle.rawValue, forKey: "islandStyle") }
    }
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle { animationStyle }
    var preferredDisplayID: String? { nil }

    private init() {
        animationStyle = UserDefaults.standard.string(forKey: "islandStyle")
            .flatMap(UnlockAnimationStyle.init(rawValue:)) ?? .original
    }
}

struct OnboardingNotchView: View {
    let controller: OnboardingController

    var body: some View {
        EnrollStepView(controller: controller)
            .frame(width: controller.panelSize.width, height: controller.panelSize.height)
    }
}
