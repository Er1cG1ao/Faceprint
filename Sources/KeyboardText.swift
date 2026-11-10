import Foundation

enum KeyboardText {
    /// Keep surrogate pairs intact even when the receiving field requires one
    /// scalar per key event, as Privacy & Security does on this Mac.
    static func batches(_ text: String, maximumUTF16Units: Int) -> [[UInt16]] {
        let units = Array(text.utf16)
        let limit = max(1, maximumUTF16Units)
        var result: [[UInt16]] = []
        var offset = 0
        while offset < units.count {
            var end = min(offset + limit, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) {
                if end - offset == 1 { end += 1 }
                else { end -= 1 }
            }
            result.append(Array(units[offset..<end]))
            offset = end
        }
        return result
    }
}
