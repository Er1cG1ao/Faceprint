import Foundation

struct CaptureResolution: Hashable, Comparable {
    let width: Int
    let height: Int
    static let standard = [Self(width: 640, height: 480), Self(width: 1280, height: 720), hd]
    static let hd = Self(width: 1920, height: 1080)
    var label: String { "\(width)×\(height)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.width * lhs.height, lhs.width) < (rhs.width * rhs.height, rhs.width)
    }
    static func select(_ requested: Self, from available: [Self]) -> Self? {
        if available.contains(requested) { return requested }
        return available.filter { $0.width <= requested.width && $0.height <= requested.height }.max() ?? available.min()
    }
    static var preference: Self {
        let parts = UserDefaults.standard.string(forKey: "captureResolution")?.split(separator: "×")
        guard let parts, parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]),
              (1...32768).contains(w), (1...32768).contains(h) else { return hd }
        return Self(width: w, height: h)
    }
}
