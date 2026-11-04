import Foundation

/// Replies to the `v` (firmware) and `i` (device name) queries.
enum DeviceInfo: Equatable, Sendable {
    case firmware(String)
    case name(String)
}

enum DeviceInfoParser {
    private static let maxLength = 32
    private static let firmwarePrefix = "fw:"

    /// "fw:1.1.22" -> firmware. "Pulsetto_ST_02" -> name. Anything else -> nil.
    static func parse(_ reply: String) -> DeviceInfo? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix(firmwarePrefix) {
            let version = text.dropFirst(firmwarePrefix.count).trimmingCharacters(in: .whitespaces)
            return isToken(version, extra: ".-+") ? .firmware(version) : nil
        }
        if text.hasPrefix(BLEConstants.deviceNamePrefix), isToken(text, extra: "_-") {
            return .name(text)
        }
        return nil
    }

    /// "Pulsetto_ST_02 · firmware 1.1.22", or the part we know, or nil.
    static func footer(name: String?, firmware: String?) -> String? {
        let parts = [name, firmware.map { "firmware \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func isToken(_ s: String, extra: String) -> Bool {
        guard !s.isEmpty, s.count <= maxLength else { return false }
        return s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || extra.contains($0) }
    }
}
