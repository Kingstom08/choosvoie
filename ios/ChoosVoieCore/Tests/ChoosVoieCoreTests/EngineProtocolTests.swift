import XCTest
import ChoosVoieCore

/// SPEC §7 X1–X3: engine protocols are implementable by plain Sendable mocks.

private struct MockEntitlementProvider: EntitlementProvider {
    func currentTier() async -> Tier { .normal }
}

private struct MockTranscriptionEngine: TranscriptionEngine {
    let id = "mock-transcriber"
    let requiresNetwork = false

    func availability(for locale: Locale) async -> EngineAvailability { .ready }

    func transcribe(audio: URL, range: TimeRange?, locale: Locale)
        -> AsyncThrowingStream<TranscriptionEvent, any Error>
    {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(0.5))
            continuation.yield(.segment(TranscriptSegment(
                range: TimeRange(start: 1, end: 2), text: "Merhaba",
                words: [TranscriptWord(text: "Merhaba", range: TimeRange(start: 1, end: 2))])))
            continuation.finish()
        }
    }
}

private struct MockSeparationEngine: SeparationEngine {
    var method: SeparationMethod { .light }
    var requiresNetwork: Bool { false }
    func canHandle(_ info: AudioTrackInfo) async -> Bool { info.channelCount == 2 }
    func separateSegment(source: URL, range: TimeRange, into output: URL) async throws {}
}

final class EngineProtocolTests: XCTestCase {

    func test_X1_mocksConformToProtocols() {
        let e: any EntitlementProvider = MockEntitlementProvider()
        let t: any TranscriptionEngine = MockTranscriptionEngine()
        let s: any SeparationEngine = MockSeparationEngine()
        XCTAssertEqual(t.id, "mock-transcriber")
        XCTAssertFalse(t.requiresNetwork)
        XCTAssertEqual(s.method, .light)
        XCTAssertFalse(s.requiresNetwork)
        XCTAssertTrue(type(of: e) == MockEntitlementProvider.self)
        XCTAssertEqual(SeparationMethod.coreml.rawValue, "coreml")
        XCTAssertEqual(Tier.pro.rawValue, "pro")
        XCTAssertNotEqual(EngineAvailability.needsDownload(bytes: 10), .needsDownload(bytes: nil))
    }

    func test_X2_entitlementTierIsNormal() async {
        let provider: any EntitlementProvider = MockEntitlementProvider()
        let tier = await provider.currentTier()
        XCTAssertEqual(tier, .normal)

        let engine: any TranscriptionEngine = MockTranscriptionEngine()
        let availability = await engine.availability(for: Locale(identifier: "tr_TR"))
        XCTAssertEqual(availability, .ready)

        let sep: any SeparationEngine = MockSeparationEngine()
        let stereo = await sep.canHandle(AudioTrackInfo(channelCount: 2, sampleRate: 48_000, durationSec: 10))
        XCTAssertTrue(stereo)
    }

    func test_X3_transcriptionStreamYieldsEventsInOrder() async throws {
        let engine: any TranscriptionEngine = MockTranscriptionEngine()
        let stream = engine.transcribe(audio: URL(fileURLWithPath: "audio.caf"),
                                       range: nil, locale: Locale(identifier: "tr_TR"))
        var events: [TranscriptionEvent] = []
        for try await event in stream {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        guard case .progress(let p) = events[0] else { return XCTFail("expected .progress, got \(events[0])") }
        XCTAssertEqual(p, 0.5)
        guard case .segment(let seg) = events[1] else { return XCTFail("expected .segment, got \(events[1])") }
        XCTAssertEqual(seg.text, "Merhaba")
        XCTAssertEqual(seg.range, TimeRange(start: 1, end: 2))
        XCTAssertEqual(seg.words?.count, 1)
    }
}
