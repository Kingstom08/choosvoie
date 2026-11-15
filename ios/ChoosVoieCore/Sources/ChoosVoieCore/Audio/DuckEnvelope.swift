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
        let count = buffer.count
        if count == 0 { return }
        guard let first = keyframes.first else {
            for i in 0..<count { buffer[i] = 1.0 }
            return
        }
        // Arabellek sonu (hariç) Int64 taşmasına karşı doygun hesaplanır.
        let (endSum, overflow) = startSample.addingReportingOverflow(Int64(count))
        let end: Int64 = overflow ? Int64.max : endSum

        var i = 0
        var n = startSample
        // İlk keyframe öncesi: 1.0
        if n < first.sample {
            let stop = min(end, first.sample)
            let len = Int(stop - n)
            for j in 0..<len { buffer[i + j] = 1.0 }
            i += len
            n = stop
        }
        if i >= count { return }

        // n >= first.sample: başlangıç keyframe'ini bir kez ikili aramayla bul.
        var lo = 0
        var hi = keyframes.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if keyframes[mid].sample <= n { lo = mid } else { hi = mid - 1 }
        }

        while i < count {
            let k = keyframes[lo]
            let hasNext = lo + 1 < keyframes.count
            let segEnd: Int64 = hasNext ? keyframes[lo + 1].sample : Int64.max
            let stop = min(end, segEnd)
            if stop <= n {
                // Aynı örnekte yinelenen keyframe: sonrakine geç.
                if hasNext { lo += 1; continue }
                break
            }
            let len = Int(stop - n)
            if !hasNext || k.curveToNext == nil || segEnd <= k.sample {
                let g = k.gain
                for j in 0..<len { buffer[i + j] = g }
            } else {
                for j in 0..<len { buffer[i + j] = gain(atSample: n + Int64(j)) }
            }
            i += len
            n = stop
            if hasNext && n >= segEnd { lo += 1 }
        }
        // Örnek indeksi Int64.max'ta doygun: taşan kalan elemanlar Int64.max değerini alır.
        if i < count {
            let g = gain(atSample: Int64.max)
            for j in i..<count { buffer[j] = g }
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
