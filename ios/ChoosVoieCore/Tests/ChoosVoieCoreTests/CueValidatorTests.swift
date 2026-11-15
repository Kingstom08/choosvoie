import XCTest
import ChoosVoieCore

/// SPEC §7 V1–V21 (app.py:514-546, 620-631).
final class CueValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func assertOK(
        _ r: Result<ValidatedCueFields, CueValidationError>,
        _ start: Double, _ end: Double, _ text: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch r {
        case .success(let v):
            XCTAssertEqual(v.startSec, start, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(v.endSec, end, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(v.text, text, file: file, line: line)
        case .failure(let e):
            XCTFail("Expected success, got \(e) (\(e.message))", file: file, line: line)
        }
    }

    private func assertSuccess(
        _ r: Result<ValidatedCueFields, CueValidationError>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        if case .failure(let e) = r {
            XCTFail("Expected success, got \(e) (\(e.message))", file: file, line: line)
        }
    }

    private func assertError(
        _ r: Result<ValidatedCueFields, CueValidationError>,
        _ expected: CueValidationError, message: String? = nil,
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

    // MARK: - Numeric overload

    func test_V1_trimsTextAndAcceptsValidCue() {
        assertOK(CueValidator.validate(startSec: 1.0, endSec: 2.0, text: "  Merhaba ", videoDurationSec: nil),
                 1.0, 2.0, "Merhaba")
    }

    func test_V2_zeroStartIsValid() {
        assertOK(CueValidator.validate(startSec: 0, endSec: 0.5, text: "a"), 0, 0.5, "a")
    }

    func test_V3_nanStartIsInvalidNumber() {
        assertError(CueValidator.validate(startSec: .nan, endSec: 1, text: "a"),
                    .invalidNumber, message: "Sayısal değer geçersiz")
    }

    func test_V4_infiniteEndIsInvalidNumber() {
        assertError(CueValidator.validate(startSec: 0, endSec: .infinity, text: "a"), .invalidNumber)
    }

    func test_V5_endAboveMaxCueSecIsInvalidNumber() {
        assertError(CueValidator.validate(startSec: 86400, endSec: 86400.5, text: "a"), .invalidNumber)
    }

    func test_V6_endExactlyAtMaxCueSecIsValid() {
        assertOK(CueValidator.validate(startSec: 86399, endSec: 86400, text: "a"), 86399, 86400, "a")
    }

    func test_V7_negativeStart() {
        assertError(CueValidator.validate(startSec: -0.1, endSec: 1, text: "a"),
                    .negativeStart, message: "Başlangıç 0 veya üstü olmalı")
    }

    func test_V8_endEqualToStart() {
        assertError(CueValidator.validate(startSec: 2, endSec: 2, text: "a"),
                    .endNotAfterStart, message: "Bitiş, başlangıçtan büyük olmalı")
    }

    func test_V9_endBeforeStart() {
        assertError(CueValidator.validate(startSec: 3, endSec: 2, text: "a"), .endNotAfterStart)
    }

    func test_V10_whitespaceOnlyTextIsEmpty() {
        assertError(CueValidator.validate(startSec: 1, endSec: 2, text: "   "),
                    .emptyText, message: "Metin boş olamaz")
    }

    func test_V11_negativeStartCheckedBeforeEndAndText() {
        assertError(CueValidator.validate(startSec: -1, endSec: -2, text: ""), .negativeStart)
    }

    func test_V12_invalidNumberCheckedFirst() {
        assertError(CueValidator.validate(startSec: .nan, endSec: 2, text: ""), .invalidNumber)
    }

    func test_V13_endWithinDurationTolerance() {
        let r = CueValidator.validate(startSec: 1, endSec: 10.0000005, text: "a", videoDurationSec: 10)
        assertSuccess(r)
        if case .success(let v) = r { XCTAssertEqual(v.endSec, 10.0000005) }
    }

    func test_V14_endExceedsDuration() {
        assertError(CueValidator.validate(startSec: 1, endSec: 10.5, text: "a", videoDurationSec: 10),
                    .endExceedsDuration(endSec: 10.5, durationSec: 10),
                    message: "Bitiş 10.5 sn, video süresini (10.0 sn) aşamaz.")
    }

    func test_V15_zeroDurationMeansUnknown() {
        assertSuccess(CueValidator.validate(startSec: 1, endSec: 10.5, text: "a", videoDurationSec: 0))
    }

    func test_V16_nilDurationMeansUnknown() {
        assertSuccess(CueValidator.validate(startSec: 1, endSec: 10.5, text: "a", videoDurationSec: nil))
    }

    func test_V17_pythonStripRemovesUnitSeparatorAndNbsp() {
        assertOK(CueValidator.validate(startSec: 1, endSec: 2, text: "\u{1F}x\u{A0}"), 1, 2, "x")
    }

    // MARK: - String overload (Python float(str) parity)

    func test_V18_commaDecimalIsInvalidNumber() {
        assertError(CueValidator.validate(startText: "1,5", endText: "2", text: "a"), .invalidNumber)
    }

    func test_V19_surroundingWhitespaceIsTrimmed() {
        assertOK(CueValidator.validate(startText: " 1.5 ", endText: "2", text: "a"), 1.5, 2.0, "a")
    }

    func test_V20_hexStringIsRejected() {
        assertError(CueValidator.validate(startText: "0x10", endText: "20", text: "a"), .invalidNumber)
    }

    func test_V21_nonNumericStringIsInvalidNumber() {
        assertError(CueValidator.validate(startText: "abc", endText: "2", text: "a"), .invalidNumber)
    }

    func test_R7_nulInTextIsInvalidNumber() {
        assertError(CueValidator.validate(startText: "1\u{0}x", endText: "2", text: "a"), .invalidNumber)
        assertError(CueValidator.validate(startText: "1", endText: "2\u{0}", text: "a"), .invalidNumber)
    }
}
