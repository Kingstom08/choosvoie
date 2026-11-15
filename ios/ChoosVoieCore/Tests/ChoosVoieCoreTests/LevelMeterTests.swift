import XCTest
import ChoosVoieCore

/// SPEC §7 L1–L12, T1–T3. 48 kHz; sq(a, n) = n samples alternating ±a; z(n) = n zeros.
/// Window = 960 samples, min silence = 9600 samples. Values recomputed with a Python model.
final class LevelMeterTests: XCTestCase {

    private let sr = 48_000

    private func sq(_ a: Float, _ n: Int) -> [Float] {
        (0..<n).map { $0 % 2 == 0 ? a : -a }
    }

    private func z(_ n: Int) -> [Float] { [Float](repeating: 0, count: n) }

    private func measure(_ x: [Float]) -> LevelMeasurement? {
        LevelMeter.measure(samples: x, sampleRate: sr)
    }

    // MARK: - LevelMeter

    func test_L1_fullScaleHalfSquare() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 48000)))
        XCTAssertEqual(m.meanDB, -6.020599913279624, accuracy: 1e-9)
        XCTAssertEqual(m.peakDB, -6.020599913279624, accuracy: 1e-9)
        XCTAssertEqual(m.measuredSampleCount, 48000)
    }

    func test_L2_quarterSquare() throws {
        let m = try XCTUnwrap(measure(sq(0.25, 48000)))
        XCTAssertEqual(m.meanDB, -12.041199826559248, accuracy: 1e-9)
        XCTAssertEqual(m.peakDB, -12.041199826559248, accuracy: 1e-9)
    }

    func test_L3_meanOfPowersPeakOfMax() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 24000) + sq(0.25, 24000)))
        XCTAssertEqual(m.meanDB, -8.061799739838872, accuracy: 1e-9)
        XCTAssertEqual(m.peakDB, -6.020599913279624, accuracy: 1e-9)
        XCTAssertEqual(m.measuredSampleCount, 48000)
    }

    func test_L4_leadingSilenceRemoved() throws {
        let m = try XCTUnwrap(measure(z(24000) + sq(0.5, 48000)))
        XCTAssertEqual(m.meanDB, -6.020599913279624, accuracy: 1e-9)
        XCTAssertEqual(m.measuredSampleCount, 48000)
    }

    func test_L5_shortTrailingSilenceKept() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 48000) + z(4800)))
        XCTAssertEqual(m.measuredSampleCount, 52800)
        XCTAssertEqual(m.meanDB, -6.434526764861874, accuracy: 1e-9)
    }

    func test_L6_longInnerSilenceRemoved() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 24000) + z(14400) + sq(0.5, 24000)))
        XCTAssertEqual(m.measuredSampleCount, 48000)
        XCTAssertEqual(m.meanDB, -6.020599913279624, accuracy: 1e-9)
    }

    func test_L7_shortInnerSilenceKept() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 24000) + z(4800) + sq(0.5, 24000)))
        XCTAssertEqual(m.measuredSampleCount, 52800)
        XCTAssertEqual(m.meanDB, -6.434526764861874, accuracy: 1e-9)
    }

    func test_L8_innerSilenceExactlyMinIsRemoved() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 24000) + z(9600) + sq(0.5, 24000)))
        XCTAssertEqual(m.measuredSampleCount, 48000)
    }

    func test_L9_innerSilenceOneWindowShortIsKept() throws {
        let m = try XCTUnwrap(measure(sq(0.5, 24000) + z(8640) + sq(0.5, 24000)))
        XCTAssertEqual(m.measuredSampleCount, 56640)
    }

    func test_L10_belowThresholdIsSilentNil() {
        XCTAssertNil(measure(sq(0.003, 48000)))
    }

    func test_L11_justAboveThresholdIsMeasured() throws {
        let m = try XCTUnwrap(measure(sq(0.004, 48000)))
        XCTAssertEqual(m.meanDB, -47.9588, accuracy: 1e-4)
        XCTAssertEqual(m.measuredSampleCount, 48000)
    }

    func test_L12_allZerosAndEmptyAreNil() {
        XCTAssertNil(measure(z(48000)))
        XCTAssertNil(measure([]))
    }

    func test_extra_partialLastWindowCounts() throws {
        // 1000 samples = one full 960 window + a 40-sample partial window; both loud.
        let m = try XCTUnwrap(measure(sq(0.5, 1000)))
        XCTAssertEqual(m.measuredSampleCount, 1000)
    }

    // MARK: - TrimDetector

    func test_T1_leadingAndTrailingSilenceDetected() throws {
        let t = try XCTUnwrap(TrimDetector.detect(samples: z(24000) + sq(0.5, 48000) + z(14400), sampleRate: sr))
        XCTAssertEqual(t.trimStartSec, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.trimEndSec, 0.3, accuracy: 1e-9)
    }

    func test_T2_shortSilenceNotTrimmed() throws {
        let t = try XCTUnwrap(TrimDetector.detect(samples: z(4800) + sq(0.5, 48000) + z(4800), sampleRate: sr))
        XCTAssertEqual(t.trimStartSec, 0, accuracy: 1e-9)
        XCTAssertEqual(t.trimEndSec, 0, accuracy: 1e-9)
    }

    func test_T3_allSilentIsNil() {
        XCTAssertNil(TrimDetector.detect(samples: z(48000), sampleRate: sr))
        XCTAssertNil(TrimDetector.detect(samples: [], sampleRate: sr))
    }

    func test_R5_nonPositiveSampleRateReturnsNil() {
        let x = sq(0.5, 9600)
        XCTAssertNil(LevelMeter.measure(samples: x, sampleRate: 0))
        XCTAssertNil(LevelMeter.measure(samples: x, sampleRate: -48_000))
        XCTAssertNil(TrimDetector.detect(samples: x, sampleRate: 0))
        XCTAssertNil(TrimDetector.detect(samples: x, sampleRate: -1))
    }
}
