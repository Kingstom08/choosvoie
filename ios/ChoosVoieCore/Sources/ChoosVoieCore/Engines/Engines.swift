import Foundation

public struct TranscriptWord: Sendable, Hashable {
    public var text: String
    public var range: TimeRange
    public init(text: String, range: TimeRange) {
        self.text = text
        self.range = range
    }
}

public struct TranscriptSegment: Sendable, Hashable {
    public var range: TimeRange
    public var text: String
    public var words: [TranscriptWord]?
    public init(range: TimeRange, text: String, words: [TranscriptWord]? = nil) {
        self.range = range
        self.text = text
        self.words = words
    }
}

public enum TranscriptionEvent: Sendable {
    case progress(Double)
    case segment(TranscriptSegment)
}

public enum EngineAvailability: Sendable, Hashable {
    case ready
    case needsDownload(bytes: Int64?)
    case unsupported
}

public protocol TranscriptionEngine: Sendable {
    var id: String { get }
    var requiresNetwork: Bool { get }
    func availability(for locale: Locale) async -> EngineAvailability
    func transcribe(audio: URL, range: TimeRange?, locale: Locale)
        -> AsyncThrowingStream<TranscriptionEvent, any Error>
}

public enum SeparationMethod: String, Sendable, Hashable { case light, companion, cloud, coreml }

public struct AudioTrackInfo: Sendable, Hashable {
    public var channelCount: Int
    public var sampleRate: Double
    public var durationSec: Double
    public init(channelCount: Int, sampleRate: Double, durationSec: Double) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.durationSec = durationSec
    }
}

public protocol SeparationEngine: Sendable {
    var method: SeparationMethod { get }
    var requiresNetwork: Bool { get }
    func canHandle(_ info: AudioTrackInfo) async -> Bool
    func separateSegment(source: URL, range: TimeRange, into output: URL) async throws
}

public enum Tier: String, Sendable, Hashable { case normal, pro }

public protocol EntitlementProvider: Sendable {
    func currentTier() async -> Tier
}
