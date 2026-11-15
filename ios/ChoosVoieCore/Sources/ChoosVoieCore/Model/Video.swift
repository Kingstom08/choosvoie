import Foundation

public struct Video: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var title: String
    public var fileName: String
    public var durationSec: Double?
    public var hasAudio: Bool
    public var isStereo: Bool

    public init(id: Int64, title: String, fileName: String,
                durationSec: Double? = nil, hasAudio: Bool = true, isStereo: Bool = false) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.durationSec = durationSec
        self.hasAudio = hasAudio
        self.isStereo = isStereo
    }

    /// durationSec sonlu ve > 0 ise onu, değilse nil.
    public var knownDurationSec: Double? {
        guard let d = durationSec, d.isFinite, d > 0 else { return nil }
        return d
    }
}
