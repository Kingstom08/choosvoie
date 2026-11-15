import Foundation

public enum MixPlanBuilder {
    public static func build(_ input: MixPlanInput) -> Result<MixPlanBuildResult, MixPlanError> {
        let sr = input.sampleRate
        guard sr > 0 else { return .failure(.invalidSampleRate) }
        guard input.videoDurationSec.isFinite, input.videoDurationSec > 0 else {
            return .failure(.unknownDuration)
        }

        let settings = input.take.settings
        var warnings: [MixPlanWarning] = []

        var cueByID: [Int64: Cue] = [:]
        for c in input.cues where cueByID[c.id] == nil { cueByID[c.id] = c }

        let takeRecs = input.recordings.filter { $0.takeID == input.take.id }
        let recs = takeRecs.filter { cueByID[$0.cueID] != nil }
        let orphans = takeRecs.count - recs.count
        if orphans > 0 { warnings.append(.orphanRecordingsIgnored(count: orphans)) }
        if recs.isEmpty { return .failure(.noRecordings) }

        for r in recs {
            guard let c = cueByID[r.cueID] else { continue }
            if !c.startSec.isFinite || !c.endSec.isFinite
                || c.startSec > CueValidator.maxCueSec || c.endSec > CueValidator.maxCueSec {
                return .failure(.invalidCueTime(startSec: c.startSec))
            }
        }

        let ordered = recs.sorted { a, b in
            let ca = cueByID[a.cueID]!.startSec
            let cb = cueByID[b.cueID]!.startSec
            if ca != cb { return ca < cb }
            return a.id < b.id
        }

        // Arka plan işlemi
        let duck = settings.duckSettings
        let treatment: BackgroundTreatment
        switch settings.duckMode {
        case .mute:
            treatment = .hardMute
        case .duck:
            treatment = .duck(duck)
        case .separated:
            if let stem = input.stem, input.hasAudio {
                treatment = .separated(stem, crossfade: duck)
            } else {
                treatment = .duck(duck)
                warnings.append(.separatedUnavailableUsedDuck)
            }
        }

        // Zarf
        let envSettings: DuckSettings
        switch treatment {
        case .hardMute:
            envSettings = .hardMute
        case let .duck(s):
            envSettings = s
        case let .separated(_, s):
            envSettings = DuckSettings(level: 0, fadeOutSec: s.fadeOutSec, fadeInSec: s.fadeInSec,
                                       curve: s.curve, scope: s.scope, minRecoverSec: s.minRecoverSec)
        }

        let windows: [TimeRange]
        var isHardMute = false
        if case .hardMute = treatment { isHardMute = true }
        if isHardMute || envSettings.scope == .recordedCues {
            var seen = Set<Int64>()
            var w: [TimeRange] = []
            for r in ordered where seen.insert(r.cueID).inserted {
                if let c = cueByID[r.cueID] { w.append(c.range) }
            }
            windows = w
        } else {
            windows = input.cues.map { $0.range }
        }
        let envelope = DuckEnvelopeBuilder.build(windows: windows, settings: envSettings,
                                                 durationSec: input.videoDurationSec, sampleRate: sr)

        // Klipler
        var clips: [MixClip] = []
        var maxGain = max(1.0, settings.bedGain)
        for r in ordered {
            guard let cue = cueByID[r.cueID] else { continue }
            let auto = settings.autoLevel ? AutoLevel.gain(meanDB: r.meanDB, peakDB: r.peakDB) : 1.0
            let g = settings.dubMasterGain * r.gainFactor * auto
            maxGain = max(maxGain, g)

            let offset = finiteOrZero(r.offsetSec)
            let latency = finiteOrZero(r.latencyCompSec)
            let trimStart = finiteOrZero(r.trimStartSec)
            let trimEnd = finiteOrZero(r.trimEndSec)

            var start = SampleTime.samples(fromSeconds: cue.startSec + offset - latency + trimStart, sampleRate: sr)
            var trimS = max(0, SampleTime.samples(fromSeconds: trimStart, sampleRate: sr))
            let trimE = max(0, SampleTime.samples(fromSeconds: trimEnd, sampleRate: sr))
            if start < 0 {
                trimS += -start
                start = 0
            }
            clips.append(MixClip(recordingID: r.id, cueID: r.cueID, fileName: r.fileName,
                                 timelineStartSample: start, trimStartSamples: trimS,
                                 trimEndSamples: trimE, gain: Float(g)))
        }

        // Limiter
        var needsLimiter = maxGain > 1 + 1e-6
        switch treatment {
        case let .duck(s): if s.level > 0 { needsLimiter = true }
        case .separated: needsLimiter = true
        case .hardMute: break
        }

        let plan = MixPlan(
            sampleRate: sr,
            durationSamples: SampleTime.samples(fromSeconds: input.videoDurationSec, sampleRate: sr),
            hasBedAudio: input.hasAudio,
            bedGain: Float(settings.bedGain),
            treatment: treatment,
            envelope: envelope,
            clips: clips,
            limiter: needsLimiter ? .standard : nil)
        return .success(MixPlanBuildResult(plan: plan, warnings: warnings))
    }

    private static func finiteOrZero(_ v: Double) -> Double { v.isFinite ? v : 0 }
}
