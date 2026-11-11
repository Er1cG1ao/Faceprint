import AppKit
import ApplicationServices
import Security

struct PromptTarget {
    let field: AXUIElement
    let pid: pid_t
    let ownerBundleID: String
    let contextID: String

    var confirmationButton: String { contextID == "privacy" ? "the confirmation button" : (contextID.hasPrefix("finder-trash:") ? "Move to Trash" : "OK") }
    var description: String { contextID == "privacy" ? "Privacy & Security" : (contextID.hasPrefix("finder-trash:") ? "Finder authorization" : "Passwords AutoFill") }

    fileprivate static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    fileprivate static func focusedElement() -> (element: AXUIElement, pid: pid_t, app: NSRunningApplication)? {
        guard AXIsProcessTrusted(),
              let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return (element, pid, app)
    }

    private static func focusedSecureField(requireEmpty: Bool) -> (field: AXUIElement, pid: pid_t, app: NSRunningApplication)? {
        guard let focused = focusedElement() else { return nil }
        let field = focused.element
        guard attribute(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              (attribute(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
               || attribute(field, kAXRoleDescriptionAttribute) as? String == "secure text field"),
              attribute(field, kAXEnabledAttribute) as? Bool != false else { return nil }
        if requireEmpty {
            guard let value = attribute(field, kAXValueAttribute) as? String, value.isEmpty else { return nil }
        }
        return (field, focused.pid, focused.app)
    }

    static func diagnosticSummary() -> String? {
        guard let focused = focusedElement(), let bundle = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true else { return nil }
        let role = attribute(focused.element, kAXRoleAttribute) as? String ?? "unknown role"
        return "System prompt owner: \(bundle) (\(role)); no supported request matched."
    }

    static func current(requireEmpty: Bool = true) -> PromptTarget? {
        guard let focused = focusedSecureField(requireEmpty: requireEmpty),
              let bundleID = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true else { return nil }
        let contextID: String
        if bundleID == PromptPolicy.privacyBundleID {
            contextID = "privacy"
        } else {
            guard PromptPolicy.supportsOwner(bundleID),
                  let context = promptContext(for: focused.field, bundleID: bundleID) else { return nil }
            contextID = context
        }
        return PromptTarget(field: focused.field, pid: focused.pid, ownerBundleID: bundleID, contextID: contextID)
    }

    fileprivate static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = attribute(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    fileprivate static func dialogText(_ root: AXUIElement) -> [String] {
        var strings: [String] = []
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var inspected = 0
        while let (element, depth) = pending.popLast(), inspected < 180 {
            inspected += 1
            let role = attribute(element, kAXRoleAttribute) as? String
            guard role != kAXApplicationRole else { continue }
            for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = attribute(element, name) as? String { strings.append(text) }
            }
            // Values of input fields are excluded. Only static prompt text is read.
            if role == kAXStaticTextRole, let text = attribute(element, kAXValueAttribute) as? String {
                strings.append(text)
            }
            if depth < 6, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
            }
        }
        return strings
    }

    private static func promptContext(for field: AXUIElement, bundleID: String) -> String? {
        let accounts = [NSUserName(), NSFullUserName()]
        func context(_ element: AXUIElement) -> String? {
            let text = dialogText(element)
            if let system = PromptPolicy.systemDialogContext(in: text, ownerBundleID: bundleID) { return system }
            guard PromptPolicy.autofillBundleIDs.contains(bundleID) else { return nil }
            return PromptPolicy.autofillContext(in: text, accountNames: accounts)
        }
        if let topLevel = elementAttribute(field, kAXTopLevelUIElementAttribute),
           let context = context(topLevel) {
            return context
        }
        var ancestor: AXUIElement? = field
        for _ in 0..<7 {
            guard let element = ancestor,
                  attribute(element, kAXRoleAttribute) as? String != kAXApplicationRole else { break }
            if let context = context(element) {
                return context
            }
            ancestor = elementAttribute(element, kAXParentAttribute)
        }
        return nil
    }

    func isCurrent(requireEmpty: Bool = false) -> Bool {
        guard let current = Self.focusedSecureField(requireEmpty: requireEmpty) else { return false }
        return pid == current.pid && ownerBundleID == current.app.bundleIdentifier && CFEqual(field, current.field)
    }

    func verifyAppleSignature() -> Bool {
        Self.verifyAppleSignature(pid: pid, bundleID: ownerBundleID)
    }

    fileprivate static func verifyAppleSignature(pid: pid_t, bundleID: String) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let rule = "anchor apple and identifier \"\(bundleID)\"" as CFString
        guard SecRequirementCreateWithString(rule, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func maskedLength() -> Int? {
        guard let value = Self.attribute(field, kAXValueAttribute) as? String else { return nil }
        return value.utf16.count
    }

    func pressReturn() throws {
        guard let current = Self.current(requireEmpty: false), current.pid == pid,
              current.contextID == contextID, CFEqual(current.field, field),
              verifyAppleSignature(), let count = maskedLength(), count > 0 else {
            throw FillError.message("Password filled. Automatic Return stopped because the prompt changed.")
        }
        let source = !contextID.hasPrefix("autofill:") ? nil : CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            throw FillError.message("Password filled. Return could not be sent.")
        }
        down.flags = []
        up.flags = []
        post(down, up)
    }

    private func post(_ down: CGEvent, _ up: CGEvent) {
        if !contextID.hasPrefix("autofill:") {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        } else {
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }

    /// Privacy & Security's extension does not reliably receive process-targeted
    /// events. Use Glance/Hammerspoon's HID delivery there and preserve the working
    /// direct-to-process route for Passwords AutoFill.
    func type(_ bytes: Data) async throws -> Bool {
        guard let current = Self.current(), current.pid == pid,
              current.contextID == contextID, CFEqual(current.field, field), verifyAppleSignature(),
              let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, !text.contains(where: { $0.isNewline || $0 == "\t" }) else {
            throw FillError.message("The verified empty system password field is no longer focused.")
        }
        let source = !contextID.hasPrefix("autofill:") ? nil : CGEventSource(stateID: .privateState)
        let chunks = KeyboardText.batches(text, maximumUTF16Units: contextID == "privacy" ? 1 : 20)
        let events = try chunks.map { chunk -> (CGEvent, CGEvent) in
            try chunk.withUnsafeBufferPointer { buffer in
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false),
                      let base = buffer.baseAddress else { throw FillError.message("Cannot create keyboard events.") }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                down.flags = []
                up.flags = []
                return (down, up)
            }
        }
        for (down, up) in events {
            try Task.checkCancellation()
            guard isCurrent() else { throw FillError.message("Focus changed. Review the password field before retrying.") }
            post(down, up)
            try await Task.sleep(for: .milliseconds(12))
        }
        let expectedLengths = Set([text.count, text.utf16.count])
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard isCurrent() else { throw FillError.message("Focus changed before filling could be verified. Check the field.") }
            if let count = maskedLength(), expectedLengths.contains(count) { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let count = maskedLength() else { return false }
        if count == 0 { throw FillError.message("The password field is still empty. Hover the Dynamic Island to retry.") }
        throw FillError.message("The field appears partially filled. Clear it before retrying.")
    }
}

/// A visible Touch ID card and its explicit password-fallback control. No
/// keyboard Return is sent to discover the password stage or confirm a request.
struct BiometricPromptTarget {
    let root: AXUIElement
    let button: AXUIElement
    let pid: pid_t
    let ownerBundleID: String
    let contextID: String

    // Preserve the user's app choice during a scan of a nonfocused card.
    let discoveryFrontmostPID: pid_t?

    var description: String { contextID == "privacy" ? "Privacy & Security Touch ID" : (contextID.hasPrefix("finder-trash:") ? "Finder Touch ID" : "Passwords AutoFill Touch ID") }

    private static func focused() -> BiometricPromptTarget? {
        guard let focused = PromptTarget.focusedElement(), let bundleID = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true,
              PromptPolicy.supportsOwner(bundleID) else { return nil }
        var ancestor: AXUIElement? = focused.element
        var roots: [AXUIElement] = []
        for _ in 0..<8 {
            guard let element = ancestor,
                  PromptTarget.attribute(element, kAXRoleAttribute) as? String != kAXApplicationRole else { break }
            roots.append(element)
            ancestor = PromptTarget.elementAttribute(element, kAXParentAttribute)
        }
        if let top = PromptTarget.elementAttribute(focused.element, kAXTopLevelUIElementAttribute),
           !roots.contains(where: { CFEqual($0, top) }) { roots.append(top) }
        for root in roots {
            guard let button = fallbackButton(in: root) else { continue }
            var ownerPID: pid_t = 0
            guard AXUIElementGetPid(button, &ownerPID) == .success,
                  let owner = NSRunningApplication(processIdentifier: ownerPID),
                  let ownerID = owner.bundleIdentifier, PromptPolicy.supportsOwner(ownerID),
                  owner.bundleURL?.path.hasPrefix("/System/") == true,
                  let context = PromptPolicy.biometricContext(in: PromptTarget.dialogText(root), ownerBundleID: ownerID) else { continue }
            return BiometricPromptTarget(root: root, button: button, pid: ownerPID,
                                         ownerBundleID: ownerID, contextID: context, discoveryFrontmostPID: nil)
        }
        return nil
    }

    static func current() -> BiometricPromptTarget? {
        if let target = focused() { return target }
        guard AXIsProcessTrusted() else { return nil }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var candidates: [BiometricPromptTarget] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  PromptPolicy.supportsOwner(bundleID),
                  app.bundleURL?.path.hasPrefix("/System/") == true else { continue }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            var windows = PromptTarget.attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let focusedWindow = PromptTarget.elementAttribute(application, kAXFocusedWindowAttribute),
               !windows.contains(where: { CFEqual($0, focusedWindow) }) { windows.append(focusedWindow) }
            for window in windows.prefix(12) where visible(window, pid: app.processIdentifier) {
                guard let button = fallbackButton(in: window) else { continue }
                // An XPC child may belong to the extension/agent rather than
                // the application whose AXWindows exposed the card.
                var buttonPID: pid_t = 0
                guard AXUIElementGetPid(button, &buttonPID) == .success,
                      let owner = NSRunningApplication(processIdentifier: buttonPID),
                      let ownerID = owner.bundleIdentifier, PromptPolicy.supportsOwner(ownerID),
                      owner.bundleURL?.path.hasPrefix("/System/") == true,
                      let context = PromptPolicy.biometricContext(in: PromptTarget.dialogText(window), ownerBundleID: ownerID) else { continue }
                let candidate = BiometricPromptTarget(root: window, button: button, pid: buttonPID,
                    ownerBundleID: ownerID, contextID: context, discoveryFrontmostPID: frontmostPID)
                if !candidates.contains(where: { CFEqual($0.button, button) }) { candidates.append(candidate) }
            }
        }
        // Never choose between multiple simultaneous authentication requests.
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func visible(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard PromptTarget.attribute(window, kAXMinimizedAttribute) as? Bool != true,
              PromptTarget.attribute(window, "AXHidden") as? Bool != true,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        var axFrame: CGRect?
        if let position = PromptTarget.attribute(window, kAXPositionAttribute),
           let size = PromptTarget.attribute(window, kAXSizeAttribute),
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var origin = CGPoint.zero
            var dimensions = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &origin),
               AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 {
                axFrame = CGRect(origin: origin, size: dimensions)
            }
        }
        return windows.contains { info in
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return false }
            if (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid { return true }
            // XPC-hosted Settings cards can be drawn by System Settings rather
            // than their AX owner. Require matching on-screen window geometry.
            guard let axFrame, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(frame.minX - axFrame.minX) <= 12 && abs(frame.minY - axFrame.minY) <= 12
                && abs(frame.width - axFrame.width) <= 24 && abs(frame.height - axFrame.height) <= 24
        }
    }

    private static func fallbackButton(in root: AXUIElement) -> AXUIElement? {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var inspected = 0
        var buttons: [AXUIElement] = []
        while let (element, depth) = pending.popLast(), inspected < 180 {
            inspected += 1
            let role = PromptTarget.attribute(element, kAXRoleAttribute) as? String
            guard role != kAXApplicationRole else { continue }
            if role == kAXTextFieldRole,
               (PromptTarget.attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
                || PromptTarget.attribute(element, kAXRoleDescriptionAttribute) as? String == "secure text field"),
               PromptTarget.attribute(element, "AXHidden") as? Bool != true { return nil }
            if role == kAXButtonRole, PromptTarget.attribute(element, kAXEnabledAttribute) as? Bool != false,
               PromptTarget.attribute(element, "AXHidden") as? Bool != true,
               let title = (PromptTarget.attribute(element, kAXTitleAttribute) as? String)
                    ?? (PromptTarget.attribute(element, kAXDescriptionAttribute) as? String),
               PromptPolicy.isPasswordFallbackButton(title) { buttons.append(element) }
            if depth < 6, let children = PromptTarget.attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
            }
        }
        // Ambiguous or truncated trees are not a safe target for a fallback click.
        guard pending.isEmpty, buttons.count == 1 else { return nil }
        return buttons[0]
    }

    func isCurrent() -> Bool {
        if let discoveryFrontmostPID {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == discoveryFrontmostPID,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier == ownerBundleID, Self.visible(root, pid: pid),
                  let liveButton = Self.fallbackButton(in: root), CFEqual(liveButton, button),
                  PromptPolicy.biometricContext(in: PromptTarget.dialogText(root), ownerBundleID: ownerBundleID) == contextID else { return false }
            return true
        }
        guard let current = Self.focused(), current.pid == pid,
              current.ownerBundleID == ownerBundleID, current.contextID == contextID,
              CFEqual(current.button, button) else { return false }
        return true
    }

    func verifyAppleSignature() -> Bool {
        PromptTarget.verifyAppleSignature(pid: pid, bundleID: ownerBundleID)
    }

    func openPasswordField() async throws -> PromptTarget {
        try Task.checkCancellation()
        guard isCurrent(), verifyAppleSignature() else {
            throw FillError.message("Touch ID prompt changed. Password fallback was not selected.")
        }
        // Only raise the authenticated card after the enrolled face matches.
        // Input remains forbidden until macOS confirms the expected focused card.
        if discoveryFrontmostPID != nil {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            AXUIElementPerformAction(root, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(button, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        let focusDeadline = Date().addingTimeInterval(1.5)
        var focusedCard: BiometricPromptTarget?
        repeat {
            try Task.checkCancellation()
            if let current = Self.focused(), current.pid == pid, current.contextID == contextID,
               CFEqual(current.button, button), current.verifyAppleSignature() {
                focusedCard = current
                break
            }
            try await Task.sleep(for: .milliseconds(80))
        } while Date() < focusDeadline
        guard focusedCard != nil else {
            throw FillError.message("The Touch ID card could not be focused. Select it and retry.")
        }
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            throw FillError.message("Use Password could not be selected. Open the password field manually.")
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            try Task.checkCancellation()
            if let target = PromptTarget.current(requireEmpty: false) {
                guard PromptPolicy.isSameFallbackRequest(originalPID: pid, passwordPID: target.pid,
                                                        originalBundleID: ownerBundleID, passwordBundleID: target.ownerBundleID,
                                                        originalContext: contextID, passwordContext: target.contextID),
                      target.isCurrent(requireEmpty: true), target.verifyAppleSignature() else {
                    throw FillError.message("Password prompt changed or is not empty. No password was entered.")
                }
                return target
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        throw FillError.message("The expected empty password field did not appear. Focus it and choose Retry current prompt.")
    }
}

enum FillTrigger {
    case password(PromptTarget)
    case biometric(BiometricPromptTarget)

    static func current(allowBiometric: Bool) -> FillTrigger? {
        if let target = PromptTarget.current() { return .password(target) }
        if allowBiometric, let target = BiometricPromptTarget.current() { return .biometric(target) }
        return nil
    }
    var element: AXUIElement {
        switch self { case .password(let target): return target.field; case .biometric(let target): return target.button }
    }
    var description: String {
        switch self { case .password(let target): return target.description; case .biometric(let target): return target.description }
    }
    var isBiometric: Bool { if case .biometric = self { return true }; return false }
    func isCurrent() -> Bool {
        switch self { case .password(let target): return target.isCurrent(requireEmpty: true); case .biometric(let target): return target.isCurrent() }
    }
    func verifyAppleSignature() -> Bool {
        switch self { case .password(let target): return target.verifyAppleSignature(); case .biometric(let target): return target.verifyAppleSignature() }
    }
    func passwordTargetAfterRecognition() async throws -> PromptTarget {
        switch self {
        case .password(let target):
            guard target.isCurrent(requireEmpty: true) else { throw CancellationError() }
            return target
        case .biometric(let target): return try await target.openPasswordField()
        }
    }
}
