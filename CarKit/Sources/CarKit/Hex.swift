import Foundation

/// Bytes to text and back, for the log and the debug screen's raw writes.
public enum Hex {
    public static func string(_ bytes: [UInt8], separator: String = " ") -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return byte < 0x10 ? "0" + digits : digits
        }.joined(separator: separator)
    }

    /// Accepts "01 02 ff", "0102FF", "0x01, 0x02" or "01:02"; nil for anything else (odd digit count, other letters).
    public static func parse(_ text: String) -> [UInt8]? {
        let digits = text.lowercased()
            .replacingOccurrences(of: "0x", with: "")
            .filter { !" ,:;-_\n\t".contains($0) }
        guard !digits.isEmpty, digits.count % 2 == 0, digits.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// The bytes as text when they are printable, for names and versions read from the car.
    public static func ascii(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        let trimmed = bytes.last == 0 ? Array(bytes.dropLast()) : bytes
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(decoding: trimmed, as: UTF8.self)
    }
}
