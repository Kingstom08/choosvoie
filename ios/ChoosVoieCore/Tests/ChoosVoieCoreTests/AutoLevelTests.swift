import XCTest
import ChoosVoieCore

/// SPEC §7 A1–A12 (app.py:1902-1908 `_auto_gain_from`). Relative tolerance 1e-12.
/// Expected values recomputed with Python: 10 ** (g_db / 20).
final class AutoLevelTests: XCTestCase {

    private func assertGain(
        _ mean: Double?, _ peak: Double?, _ expected: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let g = AutoLevel.gain(meanDB: mean, peakDB: peak)
        XCTAssertEqual(g, expected, accuracy: abs(expected) * 1e-12, file: file, line: line)
    }

    func test_A1_unknownMeanIsUnity() { assertGain(nil, nil, 1.0) }
    func test_A2_silenceFloorIsUnity() { assertGain(-45, -3, 1.0) }
    func test_A3_justAboveFloorBoostCapped() { assertGain(-44.9, nil, 5.623413251903491) }
    func test_A4_boostCappedAt15dB() { assertGain(-40, nil, 5.623413251903491) }
    func test_A5_peakCeilingLimitsBoost() { assertGain(-30, -10, 2.8183829312644537) }
    func test_A6_peakCeilingNotBinding() { assertGain(-30, -20, 3.1622776601683795) }
    func test_A7_atTargetIsUnity() { assertGain(-20, -3, 1.0) }
    func test_A8_cutCappedAtMinus6dB() { assertGain(-10, -1, 0.5011872336272722) }
    func test_A9_cutCappedPeakZero() { assertGain(-12, 0, 0.5011872336272722) }
    func test_A10_peakForcesSmallCut() { assertGain(-25, -0.5, 0.9440608762859234) }
    func test_A11_positivePeakForcesCut() { assertGain(-18, 2, 0.7079457843841379) }
    func test_A12_peakCanCutBelowMaxCut() { assertGain(-10, 6, 0.44668359215096315) }

    func test_extra_constantsMatchAppPy() {
        XCTAssertEqual(AutoLevel.targetDB, -20)
        XCTAssertEqual(AutoLevel.maxBoostDB, 15)
        XCTAssertEqual(AutoLevel.maxCutDB, -6)
        XCTAssertEqual(AutoLevel.peakCeilDB, -1)
        XCTAssertEqual(AutoLevel.silenceFloorDB, -45)
    }

    func test_R6_nonFiniteInputs() {
        XCTAssertEqual(AutoLevel.gain(meanDB: .nan, peakDB: -3), 1.0)
        XCTAssertEqual(AutoLevel.gain(meanDB: .infinity, peakDB: nil), 1.0)
        XCTAssertEqual(AutoLevel.gain(meanDB: -30, peakDB: .infinity), 1.0)
        XCTAssertEqual(AutoLevel.gain(meanDB: -10, peakDB: .infinity), 0.5011872336272722, accuracy: 1e-12)
        XCTAssertEqual(AutoLevel.gain(meanDB: -30, peakDB: .nan), 3.1622776601683795, accuracy: 1e-12)
        XCTAssertEqual(AutoLevel.gain(meanDB: -30, peakDB: -.infinity), 3.1622776601683795, accuracy: 1e-12)
    }
}
