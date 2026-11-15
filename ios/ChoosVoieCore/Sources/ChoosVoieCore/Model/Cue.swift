import Foundation

public struct Cue: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var videoID: Int64
    public var startSec: Double
    public var endSec: Double
    public var text: String

    public init(id: Int64, videoID: Int64, startSec: Double, endSec: Double, text: String) {
        self.id = id
        self.videoID = videoID
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
    }

    public var range: TimeRange { TimeRange(start: startSec, end: endSec) }
}
