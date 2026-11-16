import Foundation

public struct LevelMeasurement: Sendable, Hashable {
    public let meanDB: Double
    public let peakDB: Double
    public let measuredSampleCount: Int
}

/// Pencere analizi (LevelMeter ve TrimDetector ortak).
struct LevelWindow {
    let start: Int
    let count: Int
    let sumSquares: Double
    let peak: Double
    let isSilent: Bool
}

enum LevelWindowing {
    static func windows(samples: [Float], sampleRate: Int) -> [LevelWindow] {
        let w = max(1, Int(SampleTime.samples(fromSeconds: LevelMeter.windowSec, sampleRate: sampleRate)))
        var out: [LevelWindow] = []
        var i = 0
        while i < samples.count {
            let n = min(w, samples.count - i)
            var sum = 0.0
            var peak = 0.0
            for j in i..<(i + n) {
                let x = Double(samples[j])
                sum += x * x
                peak = max(peak, abs(x))
            }
            out.append(LevelWindow(start: i, count: n, sumSquares: sum, peak: peak,
                                   isSilent: sum / Double(n) < 1e-5))
            i += n
        }
        return out
    }
}

public enum LevelMeter {
    public static let windowSec: Double = 0.020
    public static let silenceThresholdDB: Double = -50.0
    public static let minSilenceSec: Double = 0.2

    public static func measure(samples: [Float], sampleRate: Int) -> LevelMeasurement? {
        guard sampleRate > 0 else { return nil }
        let wins = LevelWindowing.windows(samples: samples, sampleRate: sampleRate)
        let minSilence = Int(SampleTime.samples(fromSeconds: minSilenceSec, sampleRate: sampleRate))

        var idx = 0
        while idx < wins.count && wins[idx].isSilent { idx += 1 }

        var sum = 0.0
        var peak = 0.0
        var count = 0
        while idx < wins.count {
            if wins[idx].isSilent {
                var run = idx
                var runSamples = 0
                while run < wins.count && wins[run].isSilent {
                    runSamples += wins[run].count
                    run += 1
                }
                if runSamples < minSilence {
                    for k in idx..<run {
                        sum += wins[k].sumSquares
                        peak = max(peak, wins[k].peak)
                        count += wins[k].count
                    }
                }
                idx = run
            } else {
                sum += wins[idx].sumSquares
                peak = max(peak, wins[idx].peak)
                count += wins[idx].count
                idx += 1
            }
        }
        guard count > 0, sum > 0, peak > 0 else { return nil }
        return LevelMeasurement(meanDB: 10 * log10(sum / Double(count)),
                                peakDB: 20 * log10(peak),
                                measuredSampleCount: count)
    }
}

public struct TrimResult: Sendable, Hashable {
    public let trimStartSec: Double
    public let trimEndSec: Double
}

public enum TrimDetector {
    public static func detect(samples: [Float], sampleRate: Int) -> TrimResult? {
        guard sampleRate > 0 else { return nil }
        let wins = LevelWindowing.windows(samples: samples, sampleRate: sampleRate)
        guard let firstLoud = wins.firstIndex(where: { !$0.isSilent }),
              let lastLoud = wins.lastIndex(where: { !$0.isSilent }) else { return nil }
        let minSilence = Int(SampleTime.samples(fromSeconds: LevelMeter.minSilenceSec, sampleRate: sampleRate))

        var lead = 0
        for k in 0..<firstLoud { lead += wins[k].count }
        var trail = 0
        if lastLoud + 1 < wins.count {
            for k in (lastLoud + 1)..<wins.count { trail += wins[k].count }
        }
        let sr = Double(sampleRate)
        return TrimResult(trimStartSec: lead >= minSilence ? Double(lead) / sr : 0,
                          trimEndSec: trail >= minSilence ? Double(trail) / sr : 0)
    }
}
