import Foundation

/// Python `str` davranışı yardımcıları (iç kullanım).
enum PythonText {
    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        if s.properties.isWhitespace { return true }
        return s.value >= 0x1C && s.value <= 0x1F
    }

    /// Python `str.strip()`.
    static func strip(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var a = 0
        var b = scalars.count
        while a < b && isSpace(scalars[a]) { a += 1 }
        while b > a && isSpace(scalars[b - 1]) { b -= 1 }
        if a == 0 && b == scalars.count { return text }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[a..<b])
        return String(view)
    }

    /// Python `str.splitlines()` (keepends=False).
    static func splitLines(_ text: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        var hasContent = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            switch s.value {
            case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
                result.append(String(current))
                current = String.UnicodeScalarView()
                hasContent = false
            case 0x0D:
                result.append(String(current))
                current = String.UnicodeScalarView()
                hasContent = false
                if i + 1 < scalars.count && scalars[i + 1].value == 0x0A { i += 1 }
            default:
                current.append(s)
                hasContent = true
            }
            i += 1
        }
        if hasContent { result.append(String(current)) }
        return result
    }

    /// `%.1f`
    static func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    /// `%+.1f`
    static func signedF1(_ v: Double) -> String { String(format: "%+.1f", v) }

    /// Python `float(str)` yaklaşığı: kırp, hex reddet, Double(_:).
    static func parseFloat(_ text: String) -> Double? {
        let t = strip(text)
        if t.isEmpty { return nil }
        if t.unicodeScalars.contains(where: { $0.value == 0 }) { return nil }
        if t.contains("x") || t.contains("X") { return nil }
        return Double(t)
    }
}
