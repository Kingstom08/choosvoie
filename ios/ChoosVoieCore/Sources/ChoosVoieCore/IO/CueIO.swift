import Foundation

public struct CueDraft: Sendable, Hashable {
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public init(startSec: Double, endSec: Double, text: String) {
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
    }
}

public enum CueImportMode: String, Sendable, Hashable { case append, replace }

public enum CueImportError: Error, Sendable, Hashable {
    case fileTooLarge
    case notUTF8
    case jsonMissingCuesList
    case unparseable
    case noValidCues
    case tooManyCues
    case replaceBlockedByRecordings

    public var message: String {
        switch self {
        case .fileTooLarge: return "Dosya 1MB sınırını aşıyor"
        case .notUTF8: return "Dosya UTF-8 olarak okunamadı"
        case .jsonMissingCuesList: return "JSON içinde 'cues' listesi bulunamadı"
        case .unparseable: return "Dosya ne geçerli JSON ne de SRT olarak ayrıştırılabildi"
        case .noValidCues: return "Geçerli replik bulunamadı"
        case .tooManyCues: return "En fazla 500 replik içe aktarılabilir"
        case .replaceBlockedByRecordings:
            return "Bu videoda kayıtlı dublaj sesleri var; replikleri değiştirmek onları sahipsiz bırakır. Önce dublajları sil ya da 'ekle' modunu kullan."
        }
    }
}

public struct CueImportPlan: Sendable, Hashable {
    public let mode: CueImportMode
    public let cues: [CueDraft]
    public let skippedCount: Int

    public var successMessage: String { "\(cues.count) replik içe aktarıldı" }
}

public enum CueIO {
    public static let maxImportBytes: Int = 1_048_576
    public static let maxImportCues: Int = 500

    // MARK: Export

    public static func exportedAtString(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let truncated = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: truncated)
        return pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2)
            + "T" + pad(c.hour ?? 0, 2) + ":" + pad(c.minute ?? 0, 2) + ":" + pad(c.second ?? 0, 2)
    }

    public static func exportSRT(cues: [Cue]) -> String {
        var lines: [String] = []
        for (i, c) in sortedByStart(cues).enumerated() {
            lines.append(String(i + 1))
            lines.append("\(srtTimestamp(c.startSec)) --> \(srtTimestamp(c.endSec))")
            lines.append(c.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func srtTimestamp(_ seconds: Double) -> String {
        var totalMs: Int64 = 0
        if seconds.isFinite {
            let ms = (seconds * 1000).rounded(.toNearestOrEven)
            if ms.isFinite && ms > 0 { totalMs = SampleTime.clampedInt64(ms) }
        }
        let h = totalMs / 3_600_000
        var rem = totalMs % 3_600_000
        let m = rem / 60_000
        rem %= 60_000
        let s = rem / 1000
        let ms = rem % 1000
        return pad(Int(h), 2) + ":" + pad(Int(m), 2) + ":" + pad(Int(s), 2) + "," + pad(Int(ms), 3)
    }

    public static func exportFileName(title: String, ext: String) -> String {
        var replaced = title
        if let re = try? NSRegularExpression(pattern: "[^\\w\\-]+") {
            let ns = NSString(string: title)
            replaced = re.stringByReplacingMatches(
                in: title, options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "_")
        }
        var scalars = Array(replaced.unicodeScalars)
        while let f = scalars.first, f == "_" { scalars.removeFirst() }
        while let l = scalars.last, l == "_" { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        let safe = scalars.isEmpty ? "video" : String(view)
        return "\(safe)-replikler.\(ext)"
    }

    // MARK: Helpers

    static func sortedByStart(_ cues: [Cue]) -> [Cue] {
        cues.enumerated().sorted { a, b in
            if a.element.startSec != b.element.startSec { return a.element.startSec < b.element.startSec }
            return a.offset < b.offset
        }.map { $0.element }
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        if s.count >= width { return s }
        return String(repeating: "0", count: width - s.count) + s
    }
}
