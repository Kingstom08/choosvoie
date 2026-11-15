import Foundation

public enum SegmentMerger {
    public static let defaultPad: Double = 0.5
    public static let defaultGap: Double = 1.0

    public static func merge(_ ranges: [TimeRange], durationSec: Double,
                             pad: Double = defaultPad, gap: Double = defaultGap) -> [TimeRange] {
        let knownDuration = durationSec.isFinite && durationSec > 0
        var padded: [(s: Double, e: Double)] = []
        for r in ranges {
            guard r.start.isFinite, r.end.isFinite else { continue }
            let s = max(0, r.start - pad)
            var e = r.end + pad
            if knownDuration { e = min(e, durationSec) }
            if e > s { padded.append((s, e)) }
        }
        padded.sort { a, b in a.s != b.s ? a.s < b.s : a.e < b.e }

        var merged: [(s: Double, e: Double)] = []
        for item in padded {
            if let last = merged.last, item.s - last.e < gap {
                merged[merged.count - 1].e = max(last.e, item.e)
            } else {
                merged.append(item)
            }
        }
        return merged.map { TimeRange(start: $0.s, end: $0.e) }
    }
}
