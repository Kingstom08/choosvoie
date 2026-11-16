import XCTest
import ChoosVoieCore

/// SPEC §7 P1–P11 (parseSRT, app.py:951-972) and I1–I19 (planImport, app.py:975-1075).
final class CueIOImportTests: XCTestCase {

    // MARK: - Helpers

    private func d(_ s: Double, _ e: Double, _ t: String) -> CueDraft {
        CueDraft(startSec: s, endSec: e, text: t)
    }

    private func assertDrafts(
        _ actual: [CueDraft], _ expected: [CueDraft],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "got \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.startSec, e.startSec, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.endSec, e.endSec, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.text, e.text, file: file, line: line)
        }
    }

    private func plan(
        _ s: String, mode: CueImportMode = .append, recordings: Int = 0
    ) -> Result<CueImportPlan, CueImportError> {
        CueIO.planImport(data: Data(s.utf8), mode: mode, existingRecordingCount: recordings)
    }

    @discardableResult
    private func assertOK(
        _ r: Result<CueImportPlan, CueImportError>,
        file: StaticString = #filePath, line: UInt = #line
    ) -> CueImportPlan? {
        switch r {
        case .success(let p): return p
        case .failure(let e):
            XCTFail("Expected success, got \(e) (\(e.message))", file: file, line: line)
            return nil
        }
    }

    private func assertError(
        _ r: Result<CueImportPlan, CueImportError>, _ expected: CueImportError, message: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch r {
        case .success(let p):
            XCTFail("Expected \(expected), got success \(p)", file: file, line: line)
        case .failure(let e):
            XCTAssertEqual(e, expected, file: file, line: line)
            if let message {
                XCTAssertEqual(e.message, message, file: file, line: line)
            }
        }
    }

    private let p1Text =
        "1\r\n00:00:01,000 --> 00:00:02,500\r\nMerhaba\r\ndünya\r\n\r\n2\r\n00:00:03.25 --> 00:00:04.5\r\nİkinci\r\n"

    private let i1JSON = #"{"app":"choos-voie","version":1,"cues":[{"start_sec":1.0,"end_sec":2.5,"text":" Merhaba "},{"start_sec":3,"end_sec":3,"text":"x"},{"start_sec":"4.5","end_sec":5,"text":"Dört"},"junk",{"start_sec":null,"end_sec":6,"text":"y"}]}"#

    private func jsonCues(_ items: [String]) -> String {
        #"{"cues":["# + items.joined(separator: ",") + "]}"
    }

    private func validCueJSON(_ i: Int) -> String {
        #"{"start_sec":\#(i),"end_sec":\#(i).5,"text":"c\#(i)"}"#
    }

    // MARK: - P. parseSRT

    func test_P1_crlfBlocksDotAndCommaMillis() {
        assertDrafts(CueIO.parseSRT(p1Text), [d(1.0, 2.5, "Merhaba dünya"), d(3.25, 4.5, "İkinci")])
    }

    func test_P2_blockWithoutIndex() {
        assertDrafts(CueIO.parseSRT("00:00:05,000 --> 00:00:06,000\nNo index\n"), [d(5, 6, "No index")])
    }

    func test_P3_blockWithoutTextIsSkipped() {
        assertDrafts(CueIO.parseSRT("1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03,000 --> 00:00:04,000\nB"),
                     [d(3, 4, "B")])
    }

    func test_P4_indexOnlyAndNonTimeBlocksSkipped() {
        assertDrafts(CueIO.parseSRT("1\n\nhello\n\n2\n00:00:01,000 --> 00:00:02,000\nX"), [d(1, 2, "X")])
    }

    func test_P5_millisPaddedAndTruncatedToThreeDigits() {
        assertDrafts(CueIO.parseSRT("00:00:01,2345 --> 00:00:02,0\nA"), [d(1.234, 2.0, "A")])
    }

    func test_P6_secondsComputedAsIntegerPlusMillis() {
        let out = CueIO.parseSRT("01:02:03,004 --> 01:02:04,000\nA")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.startSec, Double(3723) + 4 / 1000.0)
        XCTAssertEqual(out.first?.endSec, 3724.0)
    }

    func test_P7_trailingPositionInfoOnTimeLineIgnored() {
        assertDrafts(CueIO.parseSRT("00:00:01,000 --> 00:00:02,000 X1:40 X2:600\nA"), [d(1, 2, "A")])
    }

    func test_P8_timesAreNotValidated() {
        assertDrafts(CueIO.parseSRT("00:00:05,000 --> 00:00:04,000\nA"), [d(5, 4, "A")])
    }

    func test_P9_linesJoinedWithSpaceOnlyOuterStrip() {
        let out = CueIO.parseSRT("1\n00:00:01,000 --> 00:00:02,000\n  a  \n  b  ")
        assertDrafts(out, [d(1, 2, "a     b")])
    }

    func test_P10_whitespaceOnlyLineDoesNotSplitBlocks() {
        // app.py drops whitespace-only lines inside a block (`if ln.strip() != ""`), so single spaces.
        assertDrafts(CueIO.parseSRT("1\n00:00:01,000 --> 00:00:02,000\nA\n \n2\n00:00:03,000 --> 00:00:04,000\nB"),
                     [d(1, 2, "A 2 00:00:03,000 --> 00:00:04,000 B")])
    }

    func test_P11_emptyAndWhitespaceInput() {
        XCTAssertEqual(CueIO.parseSRT(""), [])
        XCTAssertEqual(CueIO.parseSRT("   \n\n"), [])
    }

    // MARK: - I. planImport

    func test_I1_jsonMixedRowsSkipsInvalid() {
        guard let p = assertOK(plan(i1JSON)) else { return }
        XCTAssertEqual(p.mode, .append)
        assertDrafts(p.cues, [d(1.0, 2.5, "Merhaba"), d(4.5, 5.0, "Dört")])
        XCTAssertEqual(p.skippedCount, 2)
        XCTAssertEqual(p.successMessage, "2 replik içe aktarıldı")
    }

    func test_I2_cuesNotAList() {
        assertError(plan(#"{"cues":"x"}"#), .jsonMissingCuesList,
                    message: "JSON içinde 'cues' listesi bulunamadı")
    }

    func test_I3_topLevelArray() {
        assertError(plan("[1,2]"), .jsonMissingCuesList)
    }

    func test_I4_missingCuesKey() {
        assertError(plan(#"{"foo":1}"#), .jsonMissingCuesList)
    }

    func test_I5_boolCoercedToNumber() {
        guard let p = assertOK(plan(#"{"cues":[{"start_sec":true,"end_sec":2,"text":"a"}]}"#)) else { return }
        assertDrafts(p.cues, [d(1.0, 2.0, "a")])
    }

    func test_I6_nonStringTextIsSkipped() {
        assertError(plan(#"{"cues":[{"start_sec":1,"end_sec":2,"text":5}]}"#), .noValidCues,
                    message: "Geçerli replik bulunamadı")
    }

    func test_I7_utf8BomIsStripped() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(i1JSON.utf8))
        let withBOM = CueIO.planImport(data: data, mode: .append, existingRecordingCount: 0)
        XCTAssertEqual(withBOM, plan(i1JSON))
        guard let p = assertOK(withBOM) else { return }
        XCTAssertEqual(p.cues.count, 2)
        XCTAssertEqual(p.skippedCount, 2)
    }

    func test_I8_invalidUTF8() {
        let r = CueIO.planImport(data: Data([0xFF, 0xFE, 0x41]), mode: .append, existingRecordingCount: 0)
        assertError(r, .notUTF8, message: "Dosya UTF-8 olarak okunamadı")
    }

    func test_I9_neitherJSONNorSRT() {
        assertError(plan("hello"), .unparseable,
                    message: "Dosya ne geçerli JSON ne de SRT olarak ayrıştırılabildi")
    }

    func test_I10_oneByteOverLimitIsTooLarge() {
        let data = Data(repeating: 0x20, count: 1_048_577)
        let r = CueIO.planImport(data: data, mode: .append, existingRecordingCount: 0)
        assertError(r, .fileTooLarge, message: "Dosya 1MB sınırını aşıyor")
        XCTAssertEqual(CueIO.maxImportBytes, 1_048_576)
    }

    func test_I11_exactlyAtLimitIsAccepted() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nA\n"
        var data = Data(srt.utf8)
        data.append(Data(repeating: 0x20, count: CueIO.maxImportBytes - data.count))
        XCTAssertEqual(data.count, 1_048_576)
        guard let p = assertOK(CueIO.planImport(data: data, mode: .append, existingRecordingCount: 0)) else { return }
        assertDrafts(p.cues, [d(1, 2, "A")])
    }

    func test_I12_tooManyCues() {
        let json = jsonCues((0..<501).map(validCueJSON))
        assertError(plan(json), .tooManyCues, message: "En fazla 500 replik içe aktarılabilir")
        XCTAssertEqual(CueIO.maxImportCues, 500)
    }

    func test_I13_fiveHundredValidPlusOneInvalid() {
        var items = (0..<500).map(validCueJSON)
        items.append(#"{"start_sec":3,"end_sec":1,"text":"bad"}"#)
        guard let p = assertOK(plan(jsonCues(items))) else { return }
        XCTAssertEqual(p.cues.count, 500)
        XCTAssertEqual(p.skippedCount, 1)
        XCTAssertEqual(p.cues.first?.text, "c0")
        XCTAssertEqual(p.cues.last?.text, "c499")
        XCTAssertEqual(p.successMessage, "500 replik içe aktarıldı")
    }

    func test_I14_replaceBlockedByRecordings() {
        assertError(plan(i1JSON, mode: .replace, recordings: 2), .replaceBlockedByRecordings,
                    message: "Bu videoda kayıtlı dublaj sesleri var; replikleri değiştirmek onları sahipsiz bırakır. Önce dublajları sil ya da 'ekle' modunu kullan.")
    }

    func test_I15_appendWithRecordingsIsAllowed() {
        guard let p = assertOK(plan(i1JSON, mode: .append, recordings: 2)) else { return }
        XCTAssertEqual(p.cues.count, 2)
    }

    func test_I15b_replaceWithoutRecordingsIsAllowed() {
        guard let p = assertOK(plan(i1JSON, mode: .replace, recordings: 0)) else { return }
        XCTAssertEqual(p.mode, .replace)
    }

    func test_I16_noValidCuesBeatsReplaceBlock() {
        let json = #"{"cues":[{"start_sec":3,"end_sec":1,"text":"a"}]}"#
        assertError(plan(json, mode: .replace, recordings: 2), .noValidCues)
    }

    func test_I17_srtImport() {
        guard let p = assertOK(plan(p1Text)) else { return }
        assertDrafts(p.cues, [d(1.0, 2.5, "Merhaba dünya"), d(3.25, 4.5, "İkinci")])
        XCTAssertEqual(p.skippedCount, 0)
    }

    func test_I18_validatorRulesApplied() {
        let json = #"{"cues":[{"start_sec":0,"end_sec":90000,"text":"a"},{"start_sec":-1,"end_sec":1,"text":"b"},{"start_sec":0,"end_sec":1,"text":"   "}]}"#
        assertError(plan(json), .noValidCues)
    }

    func test_I19_noDurationCheckOnImport() {
        guard let p = assertOK(plan(#"{"cues":[{"start_sec":1,"end_sec":999,"text":"a"}]}"#)) else { return }
        assertDrafts(p.cues, [d(1, 999, "a")])
    }

    func test_R8_unicodeDecimalDigitIndexLineIsSkipped() {
        assertDrafts(CueIO.parseSRT("\u{661}\n00:00:01,000 --> 00:00:02,000\nA"), [d(1.0, 2.0, "A")])
    }
}
