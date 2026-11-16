import XCTest
import ChoosVoieCore

/// SPEC §7 H6–H9 (signature v2, banker's rounding to ms).
final class CueSignatureTests: XCTestCase {

    private func r(_ s: Double, _ e: Double) -> TimeRange { TimeRange(start: s, end: e) }

    func test_H6_canonicalStringIsSortedMilliseconds() {
        XCTAssertEqual(CueSignature.canonicalString(for: [r(2.8, 3.5), r(1.0, 2.0)]),
                       "1000-2000;2800-3500;")
    }

    func test_H7_signatureIsOrderIndependentAndMatchesSHA256() {
        let a = CueSignature.signature(for: [r(1.0, 2.0), r(2.8, 3.5)])
        let b = CueSignature.signature(for: [r(2.8, 3.5), r(1.0, 2.0)])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, PortableSHA256.hash("1000-2000;2800-3500;").hexString)
        XCTAssertEqual(a.count, 64)
        XCTAssertEqual(CueSignature.version, 2)
    }

    func test_H8_halfMillisecondRoundsToEven() {
        XCTAssertEqual(CueSignature.canonicalString(for: [r(0.0625, 1.0)]), "62-1000;")
    }

    func test_H9_nonFiniteRangesAreSkipped() {
        XCTAssertEqual(CueSignature.canonicalString(for: [r(.nan, 1), r(1, 2)]), "1000-2000;")
    }

    func test_extra_emptyInputIsEmptyCanonicalString() {
        XCTAssertEqual(CueSignature.canonicalString(for: []), "")
        XCTAssertEqual(CueSignature.signature(for: []), PortableSHA256.hash("").hexString)
    }
}
