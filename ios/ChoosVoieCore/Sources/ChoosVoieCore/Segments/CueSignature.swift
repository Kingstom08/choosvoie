import Foundation

public enum CueSignature {
    public static let version: Int = 2

    public static func canonicalString(for ranges: [TimeRange]) -> String {
        var pairs: [(Int64, Int64)] = []
        for r in ranges {
            guard r.start.isFinite, r.end.isFinite else { continue }
            let s = r.start * 1000
            let e = r.end * 1000
            guard s.isFinite, e.isFinite else { continue }
            pairs.append((SampleTime.clampedInt64(s.rounded(.toNearestOrEven)),
                          SampleTime.clampedInt64(e.rounded(.toNearestOrEven))))
        }
        pairs.sort { a, b in a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }
        var out = ""
        for p in pairs { out += "\(p.0)-\(p.1);" }
        return out
    }

    public static func signature(for ranges: [TimeRange]) -> String {
        PortableSHA256.hash(canonicalString(for: ranges)).hexString
    }
}
