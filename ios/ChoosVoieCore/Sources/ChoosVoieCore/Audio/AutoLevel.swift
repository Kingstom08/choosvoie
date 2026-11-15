import Foundation

public enum AutoLevel {
    public static let targetDB: Double = -20.0
    public static let maxBoostDB: Double = 15.0
    public static let maxCutDB: Double = -6.0
    public static let peakCeilDB: Double = -1.0
    public static let silenceFloorDB: Double = -45.0

    public static func gain(meanDB: Double?, peakDB: Double?) -> Double {
        guard let mean = meanDB, mean.isFinite, mean > silenceFloorDB else { return 1.0 }
        var gDB = max(maxCutDB, min(maxBoostDB, targetDB - mean))
        if let peak = peakDB, !peak.isNaN {
            // D-15: +inf tepe -> artış yok (en çok 0 dB); -inf tepe yok sayılır.
            if peak == .infinity {
                gDB = min(gDB, 0)
            } else if peak.isFinite {
                gDB = min(gDB, peakCeilDB - peak)
            }
        }
        return pow(10.0, gDB / 20.0)
    }
}
