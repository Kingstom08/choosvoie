import Foundation

public struct TakeSettings: Sendable, Hashable {
    public var bgVolume: Int
    public var dubVolume: Int
    public var autoLevel: Bool
    public var duckMode: DuckMode
    public var duckDepth: Int
    public var fadeOutSec: Double
    public var fadeInSec: Double
    public var duckCurve: FadeCurve
    public var duckScope: DuckScope
    public var minRecoverSec: Double

    public init(bgVolume: Int = 100, dubVolume: Int = 100, autoLevel: Bool = false,
                duckMode: DuckMode = .duck, duckDepth: Int = 0,
                fadeOutSec: Double = 0.5, fadeInSec: Double = 0.5,
                duckCurve: FadeCurve = .equalPower, duckScope: DuckScope = .recordedCues,
                minRecoverSec: Double = 0) {
        self.bgVolume = bgVolume
        self.dubVolume = dubVolume
        self.autoLevel = autoLevel
        self.duckMode = duckMode
        self.duckDepth = duckDepth
        self.fadeOutSec = fadeOutSec
        self.fadeInSec = fadeInSec
        self.duckCurve = duckCurve
        self.duckScope = duckScope
        self.minRecoverSec = minRecoverSec
    }

    /// Python paritesi: varsayılanlar + duckMode .mute
    public static let pythonParity = TakeSettings(duckMode: .mute)

    public var bedGain: Double { Double(min(150, max(0, bgVolume))) / 100 }

    public var dubMasterGain: Double { Double(min(200, max(0, dubVolume))) / 100 }

    public var duckSettings: DuckSettings {
        DuckSettings(level: Float(min(100, max(0, duckDepth))) / 100,
                     fadeOutSec: fadeOutSec, fadeInSec: fadeInSec,
                     curve: duckCurve, scope: duckScope, minRecoverSec: minRecoverSec)
    }
}

public struct Take: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var videoID: Int64
    public var name: String?
    public var settings: TakeSettings

    public init(id: Int64, videoID: Int64, name: String? = nil, settings: TakeSettings = TakeSettings()) {
        self.id = id
        self.videoID = videoID
        self.name = name
        self.settings = settings
    }
}
