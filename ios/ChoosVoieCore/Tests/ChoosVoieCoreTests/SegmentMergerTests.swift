import XCTest
import ChoosVoieCore

/// SPEC §7 G1–G12 (app.py:2129-2157). pad 0.5, gap 1.0.
final class SegmentMergerTests: XCTestCase {

    private func r(_ s: Double, _ e: Double) -> TimeRange { TimeRange(start: s, end: e) }

    private func assertMerge(
        _ input: [TimeRange], duration: Double, _ expected: [(Double, Double)],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let out = SegmentMerger.merge(input, durationSec: duration)
        XCTAssertEqual(out.count, expected.count, "got \(out)", file: file, line: line)
        for (o, e) in zip(out, expected) {
            XCTAssertEqual(o.start, e.0, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(o.end, e.1, accuracy: 1e-9, file: file, line: line)
        }
    }

    func test_G1_singleRangeIsPadded() {
        assertMerge([r(1, 2)], duration: 10, [(0.5, 2.5)])
    }

    func test_G2_overlappingAfterPadMerges() {
        assertMerge([r(1, 2), r(2.8, 3.5)], duration: 10, [(0.5, 4.0)])
    }

    func test_G3_gapAboveThresholdStaysSeparate() {
        assertMerge([r(1, 2), r(4.1, 5)], duration: 10, [(0.5, 2.5), (3.6, 5.5)])
    }

    func test_G4_gapBelowThresholdMerges() {
        assertMerge([r(1, 2), r(3.9, 5)], duration: 10, [(0.5, 5.5)])
    }

    func test_G5_gapExactlyThresholdStaysSeparate() {
        assertMerge([r(1, 2), r(4.0, 5)], duration: 10, [(0.5, 2.5), (3.5, 5.5)])
    }

    func test_G6_startClampedToZero() {
        assertMerge([r(0.2, 1.0)], duration: 10, [(0.0, 1.5)])
    }

    func test_G7_endClampedToDuration() {
        assertMerge([r(9.8, 10)], duration: 10, [(9.3, 10.0)])
    }

    func test_G8_zeroDurationDoesNotClamp() {
        assertMerge([r(9.8, 10)], duration: 0, [(9.3, 10.5)])
    }

    func test_G9_rangeBeyondDurationIsDropped() {
        assertMerge([r(10.6, 11)], duration: 10, [])
    }

    func test_G10_unsortedInputIsSorted() {
        assertMerge([r(5, 6), r(1, 2)], duration: 10, [(0.5, 2.5), (4.5, 6.5)])
    }

    func test_G11_containedRangeKeepsOuterEnd() {
        assertMerge([r(1, 10), r(2, 3)], duration: 20, [(0.5, 10.5)])
    }

    func test_G12_nonFiniteRangeIsSkipped() {
        assertMerge([r(.nan, 2), r(1, 2)], duration: 10, [(0.5, 2.5)])
    }

    func test_extra_defaultsMatchSpec() {
        XCTAssertEqual(SegmentMerger.defaultPad, 0.5)
        XCTAssertEqual(SegmentMerger.defaultGap, 1.0)
        XCTAssertEqual(SegmentMerger.merge([], durationSec: 10), [])
    }
}
