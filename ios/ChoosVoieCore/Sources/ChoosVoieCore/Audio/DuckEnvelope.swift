import Foundation

public struct GainKeyframe: Sendable, Hashable {
    public let sample: Int64
    public let gain: Float
    public let curveToNext: FadeCurve?

    public init(sample: Int64, gain: Float, curveToNext: FadeCurve?) {
        self.sample = sample
        self.gain = gain
        self.curveToNext = curveToNext
    }
}

public struct DuckEnvelope: Sendable, Hashable {
    public let keyframes: [GainKeyframe]

    public init(keyframes: [GainKeyframe]) {
        self.keyframes = keyframes
    }

    public static let identity = DuckEnvelope(keyframes: [])

    public func gain(atSample n: Int64) -> Float {
        guard let first = keyframes.first, n >= first.sample else { return 1.0 }
        // Son keyframe: sample <= n (ikili arama).
        var lo = 0
        var hi = keyframes.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if keyframes[mid].sample <= n { lo = mid } else { hi = mid - 1 }
        }
        let k = keyframes[lo]
        guard lo + 1 < keyframes.count, let curve = k.curveToNext else { return k.gain }
        let next = keyframes[lo + 1]
        let p0 = k.sample
        let p1 = next.sample
        guard p1 > p0 else { return k.gain }
        let u = Double(n - p0) / Double(p1 - p0)
        let g0 = Double(k.gain)
        let g1 = Double(next.gain)
        if g0 > g1 {
            return Float(g1 + (g0 - g1) * curve.fadeOutShape(u))
        } else if g0 < g1 {
            return Float(g0 + (g1 - g0) * curve.fadeOutShape(1 - u))
        }
        return Float(g0)
    }

    public func fill(into buffer: inout [Float], startingAt startSample: Int64) {
        for i in 0..<buffer.count {
            buffer[i] = gain(atSample: startSample + Int64(i))
        }
    }
}

public enum DuckEnvelopeBuilder {
    public static func build(windows: [TimeRange], settings: DuckSettings,
                             durationSec: Double,
                             sampleRate: Int = SampleTime.defaultSampleRate) -> DuckEnvelope {
        let ds = SampleTime.samples(fromSeconds: durationSec, sampleRate: sampleRate)
        if ds <= 0 { return .identity }

        var spans: [(s: Int64, e: Int64)] = []
        for w in windows {
            guard w.start.isFinite, w.end.isFinite else { continue }
            let s = max(0, SampleTime.samples(fromSeconds: w.start, sampleRate: sampleRate))
            let e = min(ds, SampleTime.samples(fromSeconds: w.end, sampleRate: sampleRate))
            if e <= s { continue }
            spans.append((s, e))
        }
        if spans.isEmpty { return .identity }

        let fo = SampleTime.samples(fromSeconds: settings.fadeOutSec, sampleRate: sampleRate)
        let fi = SampleTime.samples(fromSeconds: settings.fadeInSec, sampleRate: sampleRate)
        let mr = SampleTime.samples(fromSeconds: settings.minRecoverSec, sampleRate: sampleRate)

        spans.sort { a, b in a.s != b.s ? a.s < b.s : a.e < b.e }
        var merged: [(s: Int64, e: Int64)] = []
        for next in spans {
            if let cur = merged.last {
                let gap = next.s - cur.e
                if gap <= 0 || gap < fo + fi + mr {
                    merged[merged.count - 1].e = max(cur.e, next.e)
                    continue
                }
            }
            merged.append(next)
        }

        let level = settings.level
        var frames: [GainKeyframe] = []
        for w in merged {
            let sA = max(0, w.s - fo)
            let sB = min(ds, w.e + fi)
            if sA < w.s { frames.append(GainKeyframe(sample: sA, gain: 1, curveToNext: settings.curve)) }
            frames.append(GainKeyframe(sample: w.s, gain: level, curveToNext: nil))
            if sB > w.e {
                frames.append(GainKeyframe(sample: w.e, gain: level, curveToNext: settings.curve))
                frames.append(GainKeyframe(sample: sB, gain: 1, curveToNext: nil))
            } else {
                frames.append(GainKeyframe(sample: w.e, gain: 1, curveToNext: nil))
            }
        }
        return DuckEnvelope(keyframes: frames)
    }
}
