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
    var retryOnHover = UserDefaults.standard.object(forKey: "retryOnHover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(retryOnHover, forKey: "retryOnHover") }
    }
    let hapticFeedbackEnabled = true
    var animationStyle: UnlockAnimationStyle {
        didSet { UserDefaults.standard.set(animationStyle.rawValue, forKey: "islandStyle") }
    }
    var showAnimation = UserDefaults.standard.object(forKey: "showAnimation") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showAnimation, forKey: "showAnimation") }
    }
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle { showAnimation ? animationStyle : .none }
    var preferredDisplayID: String? { nil }

    private init() {
        animationStyle = UserDefaults.standard.string(forKey: "islandStyle")
            .flatMap(UnlockAnimationStyle.init(rawValue:)) ?? .original
        if animationStyle == .none { animationStyle = .original; showAnimation = false }
    }
}

struct OnboardingNotchView: View {
    let controller: OnboardingController

    var body: some View {
        Group {
            if controller.step == .name { FaceNameStepView(controller: controller) }
            else { EnrollStepView(controller: controller) }
        }.frame(width: controller.panelSize.width, height: controller.panelSize.height)
            .animation(OnboardingMetrics.stepAnimation, value: controller.step)
    }
}
