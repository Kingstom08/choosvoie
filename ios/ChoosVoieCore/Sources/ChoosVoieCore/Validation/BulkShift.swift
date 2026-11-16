import Foundation

public struct BulkShiftResult: Sendable, Hashable {
    public let offsetSec: Double
    public let cues: [Cue]
}

public enum BulkShiftError: Error, Sendable, Hashable {
    case invalidNumber
    case noCues
    case wouldGoBelowZero(minStartSec: Double)
    case wouldExceedDuration(maxOffsetSec: Double, durationSec: Double)
    case wouldExceedMaxCueTime
    case needsConfirmation(recordingCount: Int)

    public var message: String {
        switch self {
        case .invalidNumber:
            return "Sayısal değer geçersiz"
        case .noCues:
            return "Kaydırılacak replik yok"
        case let .wouldGoBelowZero(minStartSec):
            return "Kaydırma \(PythonText.f1(-minStartSec + 0.0)) sn'den küçük olamaz: ilk replik 0'ın altına düşer."
        case let .wouldExceedDuration(maxOffsetSec, durationSec):
            return "Kaydırma \(PythonText.signedF1(maxOffsetSec)) sn'den büyük olamaz: son replik video süresini (\(PythonText.f1(durationSec)) sn) aşar."
        case .wouldExceedMaxCueTime:
            return "Sayısal değer geçersiz"
        case let .needsConfirmation(recordingCount):
            return "Bu videoda \(recordingCount) dublaj kaydı var; tüm replikleri kaydırmak hepsinin senkronunu bozar."
        }
    }
}

public enum BulkShift {
    public static let tolerance: Double = 1e-6

    public static func apply(offsetSec: Double, to cues: [Cue], videoDurationSec: Double?,
                             recordingCount: Int, confirmed: Bool)
        -> Result<BulkShiftResult, BulkShiftError> {
        guard offsetSec.isFinite else { return .failure(.invalidNumber) }
        guard !cues.isEmpty else { return .failure(.noCues) }

        var minStart = cues[0].startSec
        var maxEnd = cues[0].endSec
        for c in cues {
            minStart = min(minStart, c.startSec)
            maxEnd = max(maxEnd, c.endSec)
        }

        if minStart + offsetSec < -tolerance {
            return .failure(.wouldGoBelowZero(minStartSec: minStart))
        }
        if let d = videoDurationSec, d.isFinite, d > 0, maxEnd + offsetSec > d + tolerance {
            return .failure(.wouldExceedDuration(maxOffsetSec: d - maxEnd, durationSec: d))
        }
        if maxEnd + offsetSec > CueValidator.maxCueSec {
            return .failure(.wouldExceedMaxCueTime)
        }
        if recordingCount > 0 && !confirmed {
            return .failure(.needsConfirmation(recordingCount: recordingCount))
        }

        var shifted: [(Int, Cue)] = []
        shifted.reserveCapacity(cues.count)
        for (i, c) in cues.enumerated() {
            var n = c
            n.startSec = c.startSec + offsetSec
            n.endSec = c.endSec + offsetSec
            if n.startSec < 0 { n.startSec = 0 }
            shifted.append((i, n))
        }
        shifted.sort { a, b in
            if a.1.startSec != b.1.startSec { return a.1.startSec < b.1.startSec }
            return a.0 < b.0
        }
        return .success(BulkShiftResult(offsetSec: offsetSec, cues: shifted.map { $0.1 }))
    }
}
