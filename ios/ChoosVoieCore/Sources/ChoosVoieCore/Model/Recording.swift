import Foundation

public enum RecordingSource: String, Sendable, Hashable { case mic, `import` }

public struct Recording: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var takeID: Int64
    public var cueID: Int64
    public var fileName: String
    public var volume: Int
    public var meanDB: Double?
    public var peakDB: Double?
    public var durationSec: Double?
    public var latencyCompSec: Double
    public var sampleRate: Int
    public var source: RecordingSource
    public var trimStartSec: Double
    public var trimEndSec: Double
    public var offsetSec: Double

    public init(id: Int64, takeID: Int64, cueID: Int64, fileName: String,
                volume: Int = 100, meanDB: Double? = nil, peakDB: Double? = nil,
                durationSec: Double? = nil, latencyCompSec: Double = 0,
                sampleRate: Int = 48_000, source: RecordingSource = .mic,
                trimStartSec: Double = 0, trimEndSec: Double = 0, offsetSec: Double = 0) {
        self.id = id
        self.takeID = takeID
        self.cueID = cueID
        self.fileName = fileName
        self.volume = volume
        self.meanDB = meanDB
        self.peakDB = peakDB
        self.durationSec = durationSec
        self.latencyCompSec = latencyCompSec
        self.sampleRate = sampleRate
        self.source = source
        self.trimStartSec = trimStartSec
        self.trimEndSec = trimEndSec
        self.offsetSec = offsetSec
    }

    public var gainFactor: Double { Double(min(200, max(0, volume))) / 100 }
}
