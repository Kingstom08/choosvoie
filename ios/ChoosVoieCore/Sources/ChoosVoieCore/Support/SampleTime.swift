import Foundation

public enum SampleTime {
    public static let defaultSampleRate: Int = 48_000

    public static func samples(fromSeconds seconds: Double, sampleRate: Int) -> Int64 {
        guard seconds.isFinite else { return 0 }
        return clampedInt64((seconds * Double(sampleRate)).rounded(.toNearestOrAwayFromZero))
    }

    /// NaN -> 0; ±2^62 ile kırpar.
    static func clampedInt64(_ value: Double) -> Int64 {
        guard !value.isNaN else { return 0 }
        let limit: Double = 4_611_686_018_427_387_904 // 2^62
        if value >= limit { return 1 << 62 }
        if value <= -limit { return -(1 << 62) }
        return Int64(value)
    }
}
