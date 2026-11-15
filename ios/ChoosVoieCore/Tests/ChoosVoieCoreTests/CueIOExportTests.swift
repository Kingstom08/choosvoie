import XCTest
import ChoosVoieCore

/// SPEC §7 S1–S8, J1–J7, F1–F4 (app.py:875-942).
final class CueIOExportTests: XCTestCase {

    private let title = "Demo \"1\""
    private let cueA = Cue(id: 1, videoID: 1, startSec: 1.0, endSec: 2.5, text: "Merhaba")
    private let cueB = Cue(id: 2, videoID: 1, startSec: 3.25, endSec: 4.0, text: "Satır\nİki")
    private let exportedAt = Date(timeIntervalSince1970: 1_763_202_030)
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private let j1Expected = [
        "{",
        "  \"app\": \"choos-voie\",",
        "  \"version\": 1,",
        "  \"video_title\": \"Demo \\\"1\\\"\",",
        "  \"exported_at\": \"2025-11-15T10:20:30\",",
        "  \"cue_count\": 2,",
        "  \"cues\": [",
        "    {",
        "      \"start_sec\": 1.0,",
        "      \"end_sec\": 2.5,",
        "      \"text\": \"Merhaba\"",
        "    },",
        "    {",
        "      \"start_sec\": 3.25,",
        "      \"end_sec\": 4.0,",
        "      \"text\": \"Satır\\nİki\"",
        "    }",
        "  ]",
        "}",
    ].joined(separator: "\n")

    // MARK: - S. srtTimestamp

    func test_S1_zero() { XCTAssertEqual(CueIO.srtTimestamp(0), "00:00:00,000") }
    func test_S2_hoursMinutesSecondsMillis() { XCTAssertEqual(CueIO.srtTimestamp(3661.5), "01:01:01,500") }
    func test_S3_halfMillisecondRoundsToEvenDown() { XCTAssertEqual(CueIO.srtTimestamp(0.0625), "00:00:00,062") }
    func test_S4_halfMillisecondRoundsToEvenUp() { XCTAssertEqual(CueIO.srtTimestamp(0.1875), "00:00:00,188") }
    func test_S5_negativeClampsToZero() { XCTAssertEqual(CueIO.srtTimestamp(-1), "00:00:00,000") }
    func test_S6_twentyFourHours() { XCTAssertEqual(CueIO.srtTimestamp(86400), "24:00:00,000") }
    func test_S7_threeDigitHours() { XCTAssertEqual(CueIO.srtTimestamp(360000), "100:00:00,000") }

    func test_S8_nonFiniteIsZero() {
        XCTAssertEqual(CueIO.srtTimestamp(.nan), "00:00:00,000")
        XCTAssertEqual(CueIO.srtTimestamp(.infinity), "00:00:00,000")
        XCTAssertEqual(CueIO.srtTimestamp(-.infinity), "00:00:00,000")
    }

    // MARK: - J. JSON / SRT export

    func test_J1_jsonExportIsByteIdenticalToPython() {
        let out = CueIO.exportJSON(videoTitle: title, cues: [cueA, cueB], exportedAt: exportedAt, timeZone: utc)
        XCTAssertEqual(out, j1Expected)
        XCTAssertFalse(out.hasSuffix("\n"))
    }

    func test_J2_exportedAtUsesTimeZoneAndTruncatesSeconds() {
        let plus3 = TimeZone(secondsFromGMT: 10800)!
        XCTAssertEqual(CueIO.exportedAtString(exportedAt, timeZone: plus3), "2025-11-15T13:20:30")
        XCTAssertEqual(CueIO.exportedAtString(exportedAt, timeZone: utc), "2025-11-15T10:20:30")
        XCTAssertEqual(CueIO.exportedAtString(Date(timeIntervalSince1970: 1_763_202_030.9), timeZone: utc),
                       "2025-11-15T10:20:30")
        let json = CueIO.exportJSON(videoTitle: title, cues: [cueA], exportedAt: exportedAt, timeZone: plus3)
        XCTAssertTrue(json.contains("  \"exported_at\": \"2025-11-15T13:20:30\",\n"))
    }

    func test_J3_emptyCueList() {
        let out = CueIO.exportJSON(videoTitle: title, cues: [], exportedAt: exportedAt, timeZone: utc)
        let expected = [
            "{",
            "  \"app\": \"choos-voie\",",
            "  \"version\": 1,",
            "  \"video_title\": \"Demo \\\"1\\\"\",",
            "  \"exported_at\": \"2025-11-15T10:20:30\",",
            "  \"cue_count\": 0,",
            "  \"cues\": []",
            "}",
        ].joined(separator: "\n")
        XCTAssertEqual(out, expected)
        XCTAssertTrue(out.contains("\"cue_count\": 0,"))
        XCTAssertTrue(out.contains("\"cues\": []"))
    }

    func test_J4_jsonEscapingMatchesEnsureAsciiFalse() {
        let c = Cue(id: 1, videoID: 1, startSec: 1.0, endSec: 2.0, text: "a\\b\t\u{1}\u{7F}")
        let out = CueIO.exportJSON(videoTitle: "t", cues: [c], exportedAt: exportedAt, timeZone: utc)
        XCTAssertTrue(out.contains("\"text\": \"a\\\\b\\t\\u0001\u{7F}\""), out)
    }

    func test_J4b_otherEscapes() {
        // \r \b \f escaped; "/" and non-ASCII raw; other C0 controls as lowercase \u00XX.
        let c = Cue(id: 1, videoID: 1, startSec: 1.0, endSec: 2.0, text: "\r\u{8}\u{C}/ç\u{1B}")
        let out = CueIO.exportJSON(videoTitle: "t", cues: [c], exportedAt: exportedAt, timeZone: utc)
        XCTAssertTrue(out.contains("\"text\": \"\\r\\b\\f/ç\\u001b\""), out)
    }

    func test_J5_srtExport() {
        XCTAssertEqual(CueIO.exportSRT(cues: [cueA, cueB]),
                       "1\n00:00:01,000 --> 00:00:02,500\nMerhaba\n\n2\n00:00:03,250 --> 00:00:04,000\nSatır\nİki\n")
        XCTAssertEqual(CueIO.exportSRT(cues: []), "")
    }

    func test_J6_exportSortsByStart() {
        let out = CueIO.exportJSON(videoTitle: title, cues: [cueB, cueA], exportedAt: exportedAt, timeZone: utc)
        XCTAssertEqual(out, j1Expected)
        XCTAssertEqual(CueIO.exportSRT(cues: [cueB, cueA]), CueIO.exportSRT(cues: [cueA, cueB]))
    }

    func test_J7_jsonRoundTripThroughImport() {
        let json = CueIO.exportJSON(videoTitle: title, cues: [cueA, cueB], exportedAt: exportedAt, timeZone: utc)
        switch CueIO.planImport(data: Data(json.utf8), mode: .append, existingRecordingCount: 0) {
        case .success(let plan):
            XCTAssertEqual(plan.cues, [
                CueDraft(startSec: 1.0, endSec: 2.5, text: "Merhaba"),
                CueDraft(startSec: 3.25, endSec: 4.0, text: "Satır\nİki"),
            ])
            XCTAssertEqual(plan.skippedCount, 0)
            XCTAssertEqual(plan.mode, .append)
        case .failure(let e):
            XCTFail("Expected success, got \(e) (\(e.message))")
        }
    }

    // MARK: - F. exportFileName

    func test_F1_nonWordRunsBecomeUnderscoreUnicodeKept() {
        XCTAssertEqual(CueIO.exportFileName(title: "Benim Videom: Bölüm 1!", ext: "json"),
                       "Benim_Videom_Bölüm_1-replikler.json")
    }

    func test_F2_allSymbolsFallsBackToVideo() {
        XCTAssertEqual(CueIO.exportFileName(title: "!!!", ext: "srt"), "video-replikler.srt")
        XCTAssertEqual(CueIO.exportFileName(title: "", ext: "srt"), "video-replikler.srt")
    }

    func test_F3_innerUnderscoresKept() {
        XCTAssertEqual(CueIO.exportFileName(title: "a__b", ext: "json"), "a__b-replikler.json")
    }

    func test_F4_hyphensKeptAndNotStripped() {
        XCTAssertEqual(CueIO.exportFileName(title: "-x-", ext: "json"), "-x--replikler.json")
    }
}
