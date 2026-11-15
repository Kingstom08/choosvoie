import Foundation

/// İçe aktarma için iç JSON değeri.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        self = .object(try c.decode([String: JSONValue].self))
    }
}

extension CueIO {
    // MARK: Export JSON

    public static func exportJSON(videoTitle: String, cues: [Cue],
                                  exportedAt: Date, timeZone: TimeZone) -> String {
        let sorted = sortedByStart(cues)
        var out = "{\n"
        out += "  \"app\": \"choos-voie\",\n"
        out += "  \"version\": 1,\n"
        out += "  \"video_title\": \(jsonString(videoTitle)),\n"
        out += "  \"exported_at\": \(jsonString(exportedAtString(exportedAt, timeZone: timeZone))),\n"
        out += "  \"cue_count\": \(sorted.count),\n"
        if sorted.isEmpty {
            out += "  \"cues\": []\n"
        } else {
            out += "  \"cues\": [\n"
            var items: [String] = []
            for c in sorted {
                var item = "    {\n"
                item += "      \"start_sec\": \(jsonDouble(c.startSec)),\n"
                item += "      \"end_sec\": \(jsonDouble(c.endSec)),\n"
                item += "      \"text\": \(jsonString(c.text))\n"
                item += "    }"
                items.append(item)
            }
            out += items.joined(separator: ",\n")
            out += "\n  ]\n"
        }
        out += "}"
        return out
    }

    static func jsonDouble(_ v: Double) -> String {
        // Sonlu olmayan değerler geçerli JSON'da temsil edilemez; 0.0 yazılır.
        guard v.isFinite else { return "0.0" }
        let plain = "\(v)"
        if abs(v) >= 1e16 { return pythonRepr(v, exponent: true) }
        // Swift, 2^53..1e16 aralığında üstel yazabilir; Python düz yazar.
        if abs(v) >= 1e15 && plain.contains("e") { return pythonRepr(v, exponent: false) }
        return plain
    }

    /// Python repr biçimi: |v| >= 1e16 için "1e+16", "1.8014398509481984e+16".
    /// Swift description en kısa basamakları verir; yalnızca biçim dönüştürülür.
    private static func pythonRepr(_ v: Double, exponent: Bool) -> String {
        let desc = "\(abs(v))"
        let sign = v < 0 ? "-" : ""
        var mantissa = desc
        var exp = 0
        if let eIdx = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(desc[desc.startIndex..<eIdx])
            exp = Int(desc[desc.index(after: eIdx)...].replacingOccurrences(of: "+", with: "")) ?? 0
        }
        var intPart = mantissa
        var frac = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = String(mantissa[mantissa.startIndex..<dot])
            frac = String(mantissa[mantissa.index(after: dot)...])
        }
        var digits = intPart + frac
        exp += intPart.count - 1
        while digits.hasPrefix("0") && digits.count > 1 { digits.removeFirst(); exp -= 1 }
        while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
        if !exponent {
            // Yalnızca 1e15 <= |v| < 1e16 (exp == 15) için çağrılır.
            while digits.count < exp + 1 { digits += "0" }
            return sign + digits + ".0"
        }
        var m = String(digits.prefix(1))
        if digits.count > 1 { m += "." + digits.dropFirst() }
        let e = abs(exp)
        let expStr = (e < 10 ? "0" : "") + String(e)
        return sign + m + "e" + (exp < 0 ? "-" : "+") + expStr
    }

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x00..<0x20:
                let hex = String(u.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                out.unicodeScalars.append(u)
            }
        }
        out += "\""
        return out
    }

    // MARK: Import

    public static func planImport(data: Data, mode: CueImportMode,
                                  existingRecordingCount: Int)
        -> Result<CueImportPlan, CueImportError> {
        if data.count > maxImportBytes { return .failure(.fileTooLarge) }

        var bytes = data
        if bytes.count >= 3, bytes[bytes.startIndex] == 0xEF,
           bytes[bytes.startIndex + 1] == 0xBB, bytes[bytes.startIndex + 2] == 0xBF {
            bytes = Data(bytes.dropFirst(3))
        }
        guard let text = String(data: bytes, encoding: .utf8) else { return .failure(.notUTF8) }

        var drafts: [CueDraft] = []
        var skipped = 0

        if let json = try? JSONDecoder().decode(JSONValue.self, from: bytes) {
            guard case let .object(obj) = json, case let .array(items)? = obj["cues"] else {
                return .failure(.jsonMissingCuesList)
            }
            var objectCount = 0
            for item in items {
                guard case let .object(fields) = item else { continue }
                objectCount += 1
                guard let s = coerceNumber(fields["start_sec"]),
                      let e = coerceNumber(fields["end_sec"]),
                      case let .string(t)? = fields["text"] else { continue }
                if case let .success(v) = CueValidator.validate(startSec: s, endSec: e, text: t) {
                    drafts.append(CueDraft(startSec: v.startSec, endSec: v.endSec, text: v.text))
                }
            }
            skipped = objectCount - drafts.count
        } else {
            let parsed = parseSRT(text)
            if parsed.isEmpty { return .failure(.unparseable) }
            for p in parsed {
                if case let .success(v) = CueValidator.validate(startSec: p.startSec, endSec: p.endSec, text: p.text) {
                    drafts.append(CueDraft(startSec: v.startSec, endSec: v.endSec, text: v.text))
                }
            }
            skipped = parsed.count - drafts.count
        }

        if drafts.isEmpty { return .failure(.noValidCues) }
        if drafts.count > maxImportCues { return .failure(.tooManyCues) }
        if mode == .replace && existingRecordingCount > 0 { return .failure(.replaceBlockedByRecordings) }
        return .success(CueImportPlan(mode: mode, cues: drafts, skippedCount: skipped))
    }

    private static func coerceNumber(_ v: JSONValue?) -> Double? {
        guard let v else { return nil }
        switch v {
        case let .number(d): return d
        case let .bool(b): return b ? 1.0 : 0.0
        case let .string(s): return PythonText.parseFloat(s)
        case .null, .array, .object: return nil
        }
    }
}
