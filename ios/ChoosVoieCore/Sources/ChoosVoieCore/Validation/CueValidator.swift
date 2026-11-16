import Foundation

public struct ValidatedCueFields: Sendable, Hashable {
    public let startSec: Double
    public let endSec: Double
    public let text: String
}

public enum CueValidationError: Error, Sendable, Hashable {
    case invalidNumber
    case negativeStart
    case endNotAfterStart
    case emptyText
    case endExceedsDuration(endSec: Double, durationSec: Double)

    public var message: String {
        switch self {
        case .invalidNumber:
            return "Sayısal değer geçersiz"
        case .negativeStart:
            return "Başlangıç 0 veya üstü olmalı"
        case .endNotAfterStart:
            return "Bitiş, başlangıçtan büyük olmalı"
        case .emptyText:
            return "Metin boş olamaz"
        case let .endExceedsDuration(endSec, durationSec):
            return "Bitiş \(PythonText.f1(endSec)) sn, video süresini (\(PythonText.f1(durationSec)) sn) aşamaz."
        }
    }
}

public enum CueValidator {
    public static let maxCueSec: Double = 86_400
    public static let durationTolerance: Double = 1e-6

    public static func validate(startSec: Double, endSec: Double, text: String,
                                videoDurationSec: Double? = nil)
        -> Result<ValidatedCueFields, CueValidationError> {
        guard startSec.isFinite, endSec.isFinite else { return .failure(.invalidNumber) }
        if startSec > maxCueSec || endSec > maxCueSec { return .failure(.invalidNumber) }
        if startSec < 0 { return .failure(.negativeStart) }
        if endSec <= startSec { return .failure(.endNotAfterStart) }
        let stripped = PythonText.strip(text)
        if stripped.isEmpty { return .failure(.emptyText) }
        if let d = videoDurationSec, d.isFinite, d > 0, endSec > d + durationTolerance {
            return .failure(.endExceedsDuration(endSec: endSec, durationSec: d))
        }
        return .success(ValidatedCueFields(startSec: startSec, endSec: endSec, text: stripped))
    }

    public static func validate(startText: String, endText: String, text: String,
                                videoDurationSec: Double? = nil)
        -> Result<ValidatedCueFields, CueValidationError> {
        guard let s = PythonText.parseFloat(startText),
              let e = PythonText.parseFloat(endText) else {
            return .failure(.invalidNumber)
        }
        return validate(startSec: s, endSec: e, text: text, videoDurationSec: videoDurationSec)
    }
}
