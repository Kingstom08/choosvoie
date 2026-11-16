import Foundation

public struct LimiterSpec: Sendable, Hashable {
    public let ceiling: Float
    public let attackSec: Double
    public let releaseSec: Double

    public init(ceiling: Float, attackSec: Double, releaseSec: Double) {
        self.ceiling = ceiling
        self.attackSec = attackSec
        self.releaseSec = releaseSec
    }

    public static let standard = LimiterSpec(ceiling: 0.85, attackSec: 0.005, releaseSec: 0.050)
}

public struct MixClip: Sendable, Hashable {
    public let recordingID: Int64
    public let cueID: Int64
    public let fileName: String
    public let timelineStartSample: Int64
    public let trimStartSamples: Int64
    public let trimEndSamples: Int64
    public let gain: Float

    public init(recordingID: Int64, cueID: Int64, fileName: String,
                timelineStartSample: Int64, trimStartSamples: Int64,
                trimEndSamples: Int64, gain: Float) {
        self.recordingID = recordingID
        self.cueID = cueID
        self.fileName = fileName
        self.timelineStartSample = timelineStartSample
        self.trimStartSamples = trimStartSamples
        self.trimEndSamples = trimEndSamples
        self.gain = gain
    }
}

public struct MixPlan: Sendable, Hashable {
    public let sampleRate: Int
    public let durationSamples: Int64
    public let hasBedAudio: Bool
    public let bedGain: Float
    public let treatment: BackgroundTreatment
    public let envelope: DuckEnvelope
    public let clips: [MixClip]
    public let limiter: LimiterSpec?

    public init(sampleRate: Int, durationSamples: Int64, hasBedAudio: Bool, bedGain: Float,
                treatment: BackgroundTreatment, envelope: DuckEnvelope,
                clips: [MixClip], limiter: LimiterSpec?) {
        self.sampleRate = sampleRate
        self.durationSamples = durationSamples
        self.hasBedAudio = hasBedAudio
        self.bedGain = bedGain
        self.treatment = treatment
        self.envelope = envelope
        self.clips = clips
        self.limiter = limiter
    }

    public var canonicalString: String {
        var lines: [String] = []
        lines.append("mixplan/1")
        lines.append("sr=\(sampleRate)")
        lines.append("dur=\(durationSamples)")
        lines.append("bedAudio=\(hasBedAudio ? 1 : 0)")
        lines.append("bed=\(MixPlan.hexF(bedGain))")
        switch treatment {
        case .hardMute:
            lines.append("treat=mute")
        case let .duck(s):
            lines.append("treat=duck;\(MixPlan.duckCanon(s))")
        case let .separated(stem, s):
            lines.append("treat=sep;stem=\(MixPlan.esc(stem.fileName));sig=\(MixPlan.esc(stem.cueSignature));\(MixPlan.duckCanon(s))")
        }
        for k in envelope.keyframes {
            lines.append("k=\(k.sample);\(MixPlan.hexF(k.gain));\(k.curveToNext?.rawValue ?? "-")")
        }
        for c in clips {
            lines.append("c=\(c.recordingID);\(c.cueID);\(MixPlan.esc(c.fileName));\(c.timelineStartSample);\(c.trimStartSamples);\(c.trimEndSamples);\(MixPlan.hexF(c.gain))")
        }
        if let l = limiter {
            lines.append("lim=\(MixPlan.hexF(l.ceiling));\(MixPlan.hexD(l.attackSec));\(MixPlan.hexD(l.releaseSec))")
        } else {
            lines.append("lim=none")
        }
        return lines.joined(separator: "\n")
    }

    public var planHash: String {
        PortableSHA256.hash(canonicalString).hexString
    }

    // MARK: Canonical helpers

    static func hexF(_ x: Float) -> String {
        String((x == 0 ? 0 : x).bitPattern, radix: 16)
    }

    static func hexD(_ x: Double) -> String {
        String((x == 0 ? 0 : x).bitPattern, radix: 16)
    }

    static func esc(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "%": out += "%25"
            case ";": out += "%3B"
            case "\n": out += "%0A"
            case "\r": out += "%0D"
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }

    static func duckCanon(_ s: DuckSettings) -> String {
        "L=\(hexF(s.level));fo=\(hexD(s.fadeOutSec));fi=\(hexD(s.fadeInSec));c=\(s.curve.rawValue);sc=\(s.scope.rawValue);mr=\(hexD(s.minRecoverSec))"
    }
}

public enum MixPlanWarning: Sendable, Hashable {
    case separatedUnavailableUsedDuck
    case orphanRecordingsIgnored(count: Int)

    public var message: String {
        switch self {
        case .separatedUnavailableUsedDuck:
            return "Ayrılmış arka plan kullanılamadı; yumuşak geçiş uygulandı."
        case let .orphanRecordingsIgnored(count):
            return "\(count) kayıt, silinmiş repliğe ait olduğu için atlandı."
        }
    }
}

public enum MixPlanError: Error, Sendable, Hashable {
    case invalidSampleRate
    case unknownDuration
    case noRecordings
    case invalidCueTime(startSec: Double)

    public var message: String {
        switch self {
        case .invalidSampleRate: return "Geçersiz örnekleme hızı"
        case .unknownDuration: return "Video süresi bilinmiyor; montaj yapılamadı."
        case .noRecordings: return "En az bir replik kaydedilmeli"
        case let .invalidCueTime(startSec):
            return "Başlangıcı \(PythonText.f1(startSec)) sn olan repliğin zaman bilgisi geçersiz, montaj yapılamadı. Lütfen bu repliği düzenleyip tekrar deneyin."
        }
    }
}

public struct MixPlanInput: Sendable {
    public var take: Take
    public var cues: [Cue]
    public var recordings: [Recording]
    public var videoDurationSec: Double
    public var hasAudio: Bool
    public var stem: StemReference?
    public var sampleRate: Int

    public init(take: Take, cues: [Cue], recordings: [Recording], videoDurationSec: Double,
                hasAudio: Bool, stem: StemReference? = nil,
                sampleRate: Int = SampleTime.defaultSampleRate) {
        self.take = take
        self.cues = cues
        self.recordings = recordings
        self.videoDurationSec = videoDurationSec
        self.hasAudio = hasAudio
        self.stem = stem
        self.sampleRate = sampleRate
    }
}

public struct MixPlanBuildResult: Sendable, Hashable {
    public let plan: MixPlan
    public let warnings: [MixPlanWarning]
}
