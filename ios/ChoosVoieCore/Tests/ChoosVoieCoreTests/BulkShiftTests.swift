import XCTest
import ChoosVoieCore

/// SPEC §7 B1–B16 (app.py:773-868). Fixture: c1 [1–2], c2 [3–4]; duration 10; 0 recordings.
final class BulkShiftTests: XCTestCase {

    private let c1 = Cue(id: 1, videoID: 1, startSec: 1, endSec: 2, text: "bir")
    private let c2 = Cue(id: 2, videoID: 1, startSec: 3, endSec: 4, text: "iki")

    private func shift(
        _ offset: Double, cues: [Cue]? = nil, duration: Double? = 10,
        recordings: Int = 0, confirmed: Bool = false
    ) -> Result<BulkShiftResult, BulkShiftError> {
        BulkShift.apply(offsetSec: offset, to: cues ?? [c1, c2], videoDurationSec: duration,
                        recordingCount: recordings, confirmed: confirmed)
    }

    @discardableResult
    private func assertOK(
        _ r: Result<BulkShiftResult, BulkShiftError>,
        file: StaticString = #filePath, line: UInt = #line
    ) -> BulkShiftResult? {
        switch r {
        case .success(let v): return v
        case .failure(let e):
            XCTFail("Expected success, got \(e) (\(e.message))", file: file, line: line)
            return nil
        }
    }

    private func assertError(
        _ r: Result<BulkShiftResult, BulkShiftError>,
        _ expected: BulkShiftError, message: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch r {
        case .success(let v):
            XCTFail("Expected \(expected), got success \(v)", file: file, line: line)
        case .failure(let e):
            XCTAssertEqual(e, expected, file: file, line: line)
            if let message {
                XCTAssertEqual(e.message, message, file: file, line: line)
            }
        }
    }

    private func assertRanges(
        _ cues: [Cue], _ expected: [(Double, Double)],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(cues.count, expected.count, file: file, line: line)
        for (c, e) in zip(cues, expected) {
            XCTAssertEqual(c.startSec, e.0, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(c.endSec, e.1, accuracy: 1e-9, file: file, line: line)
        }
    }

    func test_B1_positiveShiftPreservesIDsAndText() {
        guard let r = assertOK(shift(0.5)) else { return }
        XCTAssertEqual(r.offsetSec, 0.5)
        assertRanges(r.cues, [(1.5, 2.5), (3.5, 4.5)])
        XCTAssertEqual(r.cues.map(\.id), [1, 2])
        XCTAssertEqual(r.cues.map(\.text), ["bir", "iki"])
        XCTAssertEqual(r.cues.map(\.videoID), [1, 1])
    }

    func test_B2_negativeShiftToExactlyZero() {
        guard let r = assertOK(shift(-1.0)) else { return }
        assertRanges(r.cues, [(0, 1), (2, 3)])
    }

    func test_B3_wouldGoBelowZero() {
        assertError(shift(-1.5), .wouldGoBelowZero(minStartSec: 1.0),
                    message: "Kaydırma -1.0 sn'den küçük olamaz: ilk replik 0'ın altına düşer.")
    }

    func test_B4_shiftToExactlyDurationIsOK() {
        guard let r = assertOK(shift(6.0)) else { return }
        assertRanges(r.cues, [(7, 8), (9, 10)])
    }

    func test_B5_wouldExceedDuration() {
        assertError(shift(6.5), .wouldExceedDuration(maxOffsetSec: 6.0, durationSec: 10.0),
                    message: "Kaydırma +6.0 sn'den büyük olamaz: son replik video süresini (10.0 sn) aşar.")
    }

    func test_B6_unknownDurationAllowsLargeShift() {
        guard let r = assertOK(shift(100, duration: nil)) else { return }
        assertRanges(r.cues, [(101, 102), (103, 104)])
    }

    func test_B7_nonFiniteOffsetIsInvalidNumber() {
        assertError(shift(.nan), .invalidNumber, message: "Sayısal değer geçersiz")
        assertError(shift(.infinity), .invalidNumber)
        assertError(shift(-.infinity), .invalidNumber)
    }

    func test_B8_noCues() {
        assertError(shift(1, cues: []), .noCues, message: "Kaydırılacak replik yok")
    }

    func test_B9_invalidNumberCheckedBeforeNoCues() {
        assertError(shift(.nan, cues: []), .invalidNumber)
    }

    func test_B10_recordingsNeedConfirmation() {
        assertError(shift(0.5, recordings: 3, confirmed: false), .needsConfirmation(recordingCount: 3),
                    message: "Bu videoda 3 dublaj kaydı var; tüm replikleri kaydırmak hepsinin senkronunu bozar.")
    }

    func test_B11_confirmedShiftWithRecordingsIsOK() {
        guard let r = assertOK(shift(0.5, recordings: 3, confirmed: true)) else { return }
        assertRanges(r.cues, [(1.5, 2.5), (3.5, 4.5)])
    }

    func test_B12_rangeErrorBeatsConfirmation() {
        assertError(shift(-1.5, recordings: 3, confirmed: false), .wouldGoBelowZero(minStartSec: 1.0))
    }

    func test_B13_belowZeroMessageHasNoNegativeZero() {
        let c = Cue(id: 5, videoID: 1, startSec: 0, endSec: 1, text: "x")
        assertError(shift(-0.5, cues: [c]), .wouldGoBelowZero(minStartSec: 0),
                    message: "Kaydırma 0.0 sn'den küçük olamaz: ilk replik 0'ın altına düşer.")
    }

    func test_B14_withinToleranceBelowZeroIsClampedToZero() {
        let c = Cue(id: 5, videoID: 1, startSec: 1, endSec: 2, text: "x")
        guard let r = assertOK(shift(-1.0000005, cues: [c])) else { return }
        XCTAssertEqual(r.cues.count, 1)
        XCTAssertEqual(r.cues.first?.startSec, 0)
        XCTAssertEqual(r.cues.first?.endSec ?? -1, 0.9999995, accuracy: 1e-9)
    }

    func test_B15_wouldExceedMaxCueTime() {
        let c = Cue(id: 5, videoID: 1, startSec: 86000, endSec: 86300, text: "x")
        assertError(shift(200, cues: [c], duration: nil), .wouldExceedMaxCueTime,
                    message: "Sayısal değer geçersiz")
    }

    func test_B16_resultIsSortedByStart() {
        guard let r = assertOK(shift(0, cues: [c2, c1])) else { return }
        XCTAssertEqual(r.cues.map(\.id), [1, 2])
        assertRanges(r.cues, [(1, 2), (3, 4)])
    }
}
