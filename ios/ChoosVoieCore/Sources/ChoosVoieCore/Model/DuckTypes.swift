import Foundation

public enum FadeCurve: String, Sendable, Hashable, CaseIterable {
    case equalPower = "equal_power"
    case linear = "linear"
    case sCurve = "s_curve"

    /// Fade-out şekli c(u); u önce [0,1]'e kırpılır. c(0)=1, c(1)=0.
    public func fadeOutShape(_ u: Double) -> Double {
        let x: Double = u.isNaN ? 0 : min(1, max(0, u))
        switch self {
        case .linear:
            return 1 - x
        case .equalPower:
            return cos(Double.pi / 2 * x)
        case .sCurve:
            return (1 + cos(Double.pi * x)) / 2
        }
    }
}

public enum DuckScope: String, Sendable, Hashable, CaseIterable {
    case recordedCues = "recorded"
    case allCues = "all"
}

public enum DuckMode: String, Sendable, Hashable, CaseIterable {
    case mute, duck, separated
}

public struct DuckSettings: Sendable, Hashable {
    public static let maxFadeSec: Double = 3.0

    public let level: Float
    public let fadeOutSec: Double
    public let fadeInSec: Double
    public let curve: FadeCurve
    public let scope: DuckScope
    public let minRecoverSec: Double

    /// Değerleri yukarıdaki aralıklara kırpar.
    public init(level: Float, fadeOutSec: Double, fadeInSec: Double,
                curve: FadeCurve = .equalPower, scope: DuckScope = .recordedCues,
                minRecoverSec: Double = 0) {
        self.level = level.isFinite ? min(1, max(0, level)) : 0
        self.fadeOutSec = DuckSettings.clampFade(fadeOutSec)
        self.fadeInSec = DuckSettings.clampFade(fadeInSec)
        self.curve = curve
        self.scope = scope
        self.minRecoverSec = DuckSettings.clampFade(minRecoverSec)
    }

    private static func clampFade(_ v: Double) -> Double {
        v.isFinite ? min(maxFadeSec, max(0, v)) : 0
    }

    public static let `default` = DuckSettings(level: 0, fadeOutSec: 0.5, fadeInSec: 0.5,
                                               curve: .equalPower, scope: .recordedCues,
                                               minRecoverSec: 0)
    public static let hardMute = DuckSettings(level: 0, fadeOutSec: 0, fadeInSec: 0,
                                              curve: .linear, scope: .recordedCues,
                                              minRecoverSec: 0)
}

public struct StemReference: Sendable, Hashable {
    public var fileName: String
    public var cueSignature: String

    public init(fileName: String, cueSignature: String) {
        self.fileName = fileName
        self.cueSignature = cueSignature
    }
}

public enum BackgroundTreatment: Sendable, Hashable {
    case hardMute
    case duck(DuckSettings)
    case separated(StemReference, crossfade: DuckSettings)
}
