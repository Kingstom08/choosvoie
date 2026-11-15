import Foundation

extension CueIO {
    /// app.py:951-972. Ham çıktı: zamanlar doğrulanmamış, metin boş değil.
    public static func parseSRT(_ text: String) -> [CueDraft] {
        guard let splitRe = try? NSRegularExpression(pattern: "\\r?\\n\\r?\\n+"),
              let timeRe = try? NSRegularExpression(
                pattern: "(\\d+):(\\d+):(\\d+)[,.](\\d+)\\s*-->\\s*(\\d+):(\\d+):(\\d+)[,.](\\d+)")
        else { return [] }

        let stripped = PythonText.strip(text)
        let ns = NSString(string: stripped)
        var blocks: [String] = []
        var last = 0
        for m in splitRe.matches(in: stripped, options: [], range: NSRange(location: 0, length: ns.length)) {
            blocks.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        blocks.append(ns.substring(with: NSRange(location: last, length: ns.length - last)))

        var result: [CueDraft] = []
        for block in blocks {
            let lines = PythonText.splitLines(block).filter { !PythonText.strip($0).isEmpty }
            if lines.isEmpty { continue }
            let idx = isAllDecimalDigits(PythonText.strip(lines[0])) ? 1 : 0
            if idx >= lines.count { continue }

            let line = NSString(string: lines[idx])
            guard let m = timeRe.firstMatch(in: lines[idx], options: [],
                                            range: NSRange(location: 0, length: line.length)),
                  let start = seconds(m, 1, line),
                  let end = seconds(m, 5, line) else { continue }

            let cueText = PythonText.strip(lines[(idx + 1)...].joined(separator: " "))
            if !cueText.isEmpty {
                result.append(CueDraft(startSec: start, endSec: end, text: cueText))
            }
        }
        return result
    }

    private static func isAllDecimalDigits(_ s: String) -> Bool {
        let scalars = s.unicodeScalars
        if scalars.isEmpty { return false }
        return scalars.allSatisfy { $0.properties.numericType == .decimal }
    }

    /// `first` .. `first+3` grupları: h, m, s, ms.
    private static func seconds(_ m: NSTextCheckingResult, _ first: Int, _ line: NSString) -> Double? {
        func group(_ i: Int) -> String { line.substring(with: m.range(at: i)) }
        guard let h = Int(group(first)), let mi = Int(group(first + 1)),
              let s = Int(group(first + 2)) else { return nil }
        var ms = group(first + 3)
        while ms.count < 3 { ms += "0" }
        guard let ms3 = Int(String(ms.prefix(3))) else { return nil }
        return Double(h) * 3600 + Double(mi) * 60 + Double(s) + Double(ms3) / 1000.0
    }
}
