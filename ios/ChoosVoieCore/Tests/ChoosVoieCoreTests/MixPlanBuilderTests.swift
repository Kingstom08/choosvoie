import XCTest
import ChoosVoieCore

/// SPEC §7 M1–M27 (app.py:2570-2784).
/// Fixture: take id 1; c1 = (id 1, 1.0–2.0); r7 = (id 7, take 1, cue 1, "a.caf"); duration 10; hasAudio true.
final class MixPlanBuilderTests: XCTestCase {

    private let eqP = FadeCurve.equalPower
    private let c1 = Cue(id: 1, videoID: 1, startSec: 1.0, endSec: 2.0, text: "bir")
    private let r7 = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf")

    private let m26Expected = [
        "mixplan/1",
        "sr=48000",
        "dur=480000",
        "bedAudio=1",
        "bed=3f800000",
        "treat=duck;L=0;fo=3fe0000000000000;fi=3fe0000000000000;c=equal_power;sc=recorded;mr=0",
        "k=24000;3f800000;equal_power",
        "k=48000;0;-",
        "k=96000;0;equal_power",
        "k=120000;3f800000;-",
        "c=7;1;a.caf;48000;0;0;3f800000",
        "lim=none",
    ].joined(separator: "\n")

    // MARK: - Helpers

    private func k(_ s: Int64, _ g: Float, _ c: FadeCurve?) -> GainKeyframe {
        GainKeyframe(sample: s, gain: g, curveToNext: c)
    }

    private func input(
        settings: TakeSettings = TakeSettings(),
        cues: [Cue]? = nil, recordings: [Recording]? = nil,
        duration: Double = 10, hasAudio: Bool = true,
        stem: StemReference? = nil, sampleRate: Int = 48_000
    ) -> MixPlanInput {
        MixPlanInput(take: Take(id: 1, videoID: 1, settings: settings),
                     cues: cues ?? [c1], recordings: recordings ?? [r7],
                     videoDurationSec: duration, hasAudio: hasAudio, stem: stem, sampleRate: sampleRate)
    }

    private func build(_ i: MixPlanInput, file: StaticString = #filePath, line: UInt = #line) -> MixPlanBuildResult? {
        switch MixPlanBuilder.build(i) {
        case .success(let r): return r
        case .failure(let e):
            XCTFail("Expected success, got \(e) (\(e.message))", file: file, line: line)
            return nil
        }
    }

    private func buildError(_ i: MixPlanInput, file: StaticString = #filePath, line: UInt = #line) -> MixPlanError? {
        switch MixPlanBuilder.build(i) {
        case .success(let r):
            XCTFail("Expected failure, got \(r)", file: file, line: line)
            return nil
        case .failure(let e): return e
        }
    }

    private func rec(_ id: Int64, cue: Int64, take: Int64 = 1, file: String? = nil) -> Recording {
        Recording(id: id, takeID: take, cueID: cue, fileName: file ?? "r\(id).caf")
    }

    // MARK: - Treatment / envelope / limiter

    func test_M1_pythonParityIsHardMute() throws {
        let r = try XCTUnwrap(build(input(settings: .pythonParity)))
        XCTAssertEqual(r.plan.treatment, .hardMute)
        XCTAssertEqual(r.plan.envelope.keyframes, [k(48000, 0, nil), k(96000, 1, nil)])
        XCTAssertEqual(r.plan.clips.count, 1)
        XCTAssertEqual(r.plan.clips.first?.timelineStartSample, 48000)
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, 1, accuracy: 1e-6)
        XCTAssertNil(r.plan.limiter)
        XCTAssertEqual(r.plan.bedGain, 1, accuracy: 1e-6)
        XCTAssertEqual(r.warnings, [])
    }

    func test_M2_defaultDuck() throws {
        let r = try XCTUnwrap(build(input()))
        XCTAssertEqual(r.plan.treatment, .duck(DuckSettings.default))
        XCTAssertEqual(r.plan.envelope.keyframes,
                       [k(24000, 1, eqP), k(48000, 0, nil), k(96000, 0, eqP), k(120000, 1, nil)])
        XCTAssertNil(r.plan.limiter)
        XCTAssertEqual(r.plan.sampleRate, 48000)
        XCTAssertEqual(r.plan.durationSamples, 480000)
        XCTAssertTrue(r.plan.hasBedAudio)
        let clip = try XCTUnwrap(r.plan.clips.first)
        XCTAssertEqual(clip, MixClip(recordingID: 7, cueID: 1, fileName: "a.caf", timelineStartSample: 48000,
                                     trimStartSamples: 0, trimEndSamples: 0, gain: 1))
    }

    func test_M3_duckDepthEnablesLimiter() throws {
        let r = try XCTUnwrap(build(input(settings: TakeSettings(duckDepth: 20))))
        XCTAssertEqual(r.plan.limiter, .standard)
        XCTAssertEqual(r.plan.envelope.gain(atSample: 72000), 0.2, accuracy: 1e-6)
        guard case .duck(let s) = r.plan.treatment else { return XCTFail("expected .duck, got \(r.plan.treatment)") }
        XCTAssertEqual(s.level, 0.2, accuracy: 1e-6)
        XCTAssertTrue(r.plan.canonicalString.hasSuffix("\nlim=3f59999a;3f747ae147ae147b;3fa999999999999a"))
    }

    func test_M4_bedGainAboveUnityEnablesLimiter() throws {
        let r = try XCTUnwrap(build(input(settings: TakeSettings(bgVolume: 150))))
        XCTAssertEqual(r.plan.bedGain, 1.5, accuracy: 1e-6)
        XCTAssertEqual(r.plan.limiter, .standard)
    }

    func test_M5_bedGainClampedTo150Percent() throws {
        let r = try XCTUnwrap(build(input(settings: TakeSettings(bgVolume: 200))))
        XCTAssertEqual(r.plan.bedGain, 1.5, accuracy: 1e-6)
    }

    func test_M6_dubMasterAboveUnity() throws {
        let r = try XCTUnwrap(build(input(settings: TakeSettings(dubVolume: 120))))
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, 1.2, accuracy: 1e-6)
        XCTAssertEqual(r.plan.limiter, .standard)
    }

    func test_M7_dubMasterTimesRecordingVolumeIsUnity() throws {
        let r200 = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf", volume: 200)
        let r = try XCTUnwrap(build(input(settings: TakeSettings(dubVolume: 50), recordings: [r200])))
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, 1.0, accuracy: 1e-6)
        XCTAssertNil(r.plan.limiter)
    }

    func test_M8_autoLevelGainApplied() throws {
        let lv = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf", meanDB: -30, peakDB: -10)
        let r = try XCTUnwrap(build(input(settings: TakeSettings(autoLevel: true), recordings: [lv])))
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, Float(2.8183829312644537), accuracy: 1e-6)
        XCTAssertEqual(r.plan.limiter, .standard)
    }

    func test_M9_autoLevelWithoutMeasurementIsUnity() throws {
        let r = try XCTUnwrap(build(input(settings: TakeSettings(autoLevel: true))))
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, 1.0, accuracy: 1e-6)
    }

    func test_M10_autoLevelOffIgnoresMeasurement() throws {
        let lv = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf", meanDB: -30)
        let r = try XCTUnwrap(build(input(settings: TakeSettings(autoLevel: false), recordings: [lv])))
        XCTAssertEqual(r.plan.clips.first?.gain ?? -1, 1.0, accuracy: 1e-6)
    }

    func test_M11_separatedWithStem() throws {
        let stem = StemReference(fileName: "bg.caf", cueSignature: "sig")
        let r = try XCTUnwrap(build(input(settings: TakeSettings(duckMode: .separated, duckDepth: 20), stem: stem)))
        guard case .separated(let s, _) = r.plan.treatment else {
            return XCTFail("expected .separated, got \(r.plan.treatment)")
        }
        XCTAssertEqual(s, stem)
        XCTAssertEqual(r.plan.envelope.gain(atSample: 72000), 0, accuracy: 1e-6)
        XCTAssertEqual(r.plan.limiter, .standard)
        XCTAssertEqual(r.warnings, [])
    }

    func test_M12_separatedWithoutStemFallsBackToDuck() throws {
        let settings = TakeSettings(duckMode: .separated)
        let r = try XCTUnwrap(build(input(settings: settings)))
        XCTAssertEqual(r.plan.treatment, .duck(settings.duckSettings))
        XCTAssertEqual(r.warnings, [.separatedUnavailableUsedDuck])
        XCTAssertEqual(MixPlanWarning.separatedUnavailableUsedDuck.message,
                       "Ayrılmış arka plan kullanılamadı; yumuşak geçiş uygulandı.")
        XCTAssertNil(r.plan.limiter)
    }

    func test_M13_separatedWithoutBedAudioFallsBackToDuck() throws {
        let stem = StemReference(fileName: "bg.caf", cueSignature: "sig")
        let settings = TakeSettings(duckMode: .separated)
        let r = try XCTUnwrap(build(input(settings: settings, hasAudio: false, stem: stem)))
        XCTAssertEqual(r.plan.treatment, .duck(settings.duckSettings))
        XCTAssertEqual(r.warnings, [.separatedUnavailableUsedDuck])
        XCTAssertFalse(r.plan.hasBedAudio)
    }

    // MARK: - Errors

    func test_M14_noRecordings() throws {
        let e = try XCTUnwrap(buildError(input(recordings: [])))
        XCTAssertEqual(e, .noRecordings)
        XCTAssertEqual(e.message, "En az bir replik kaydedilmeli")
    }

    func test_M15_recordingsOfOtherTakeIgnored() throws {
        let e = try XCTUnwrap(buildError(input(recordings: [rec(7, cue: 1, take: 2)])))
        XCTAssertEqual(e, .noRecordings)
    }

    func test_M16_cueStartAboveMaxIsInvalidCueTime() throws {
        let bad = Cue(id: 1, videoID: 1, startSec: 90000, endSec: 2.0, text: "bir")
        let e = try XCTUnwrap(buildError(input(cues: [bad])))
        XCTAssertEqual(e, .invalidCueTime(startSec: 90000))
        XCTAssertEqual(e.message,
                       "Başlangıcı 90000.0 sn olan repliğin zaman bilgisi geçersiz, montaj yapılamadı. Lütfen bu repliği düzenleyip tekrar deneyin.")
    }

    func test_M17_nanCueStartIsInvalidCueTime() throws {
        let bad = Cue(id: 1, videoID: 1, startSec: .nan, endSec: 2.0, text: "bir")
        let e = try XCTUnwrap(buildError(input(cues: [bad])))
        guard case .invalidCueTime = e else { return XCTFail("expected invalidCueTime, got \(e)") }
    }

    func test_M18_unknownDuration() throws {
        for d in [0.0, .nan, -1, .infinity] {
            let e = try XCTUnwrap(buildError(input(duration: d)))
            XCTAssertEqual(e, .unknownDuration, "duration \(d)")
        }
        XCTAssertEqual(MixPlanError.unknownDuration.message, "Video süresi bilinmiyor; montaj yapılamadı.")
    }

    func test_M19_invalidSampleRate() throws {
        let e = try XCTUnwrap(buildError(input(sampleRate: 0)))
        XCTAssertEqual(e, .invalidSampleRate)
        XCTAssertEqual(e.message, "Geçersiz örnekleme hızı")
        // invalidSampleRate is checked before everything else.
        let e2 = try XCTUnwrap(buildError(input(recordings: [], duration: .nan, sampleRate: -1)))
        XCTAssertEqual(e2, .invalidSampleRate)
    }

    // MARK: - Clip placement

    func test_M20_negativeStartShiftsIntoTrim() throws {
        let c = Cue(id: 1, videoID: 1, startSec: 0.0, endSec: 1.0, text: "bir")
        let lat = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf", latencyCompSec: 0.02)
        let r = try XCTUnwrap(build(input(cues: [c], recordings: [lat])))
        let clip = try XCTUnwrap(r.plan.clips.first)
        XCTAssertEqual(clip.timelineStartSample, 0)
        XCTAssertEqual(clip.trimStartSamples, 960)
    }

    func test_M21_offsetLatencyAndTrims() throws {
        let rr = Recording(id: 7, takeID: 1, cueID: 1, fileName: "a.caf", latencyCompSec: 0.01,
                           trimStartSec: 0.2, trimEndSec: 0.3, offsetSec: 0.1)
        let r = try XCTUnwrap(build(input(recordings: [rr])))
        let clip = try XCTUnwrap(r.plan.clips.first)
        XCTAssertEqual(clip.timelineStartSample, 61920)
        XCTAssertEqual(clip.trimStartSamples, 9600)
        XCTAssertEqual(clip.trimEndSamples, 14400)
    }

    func test_M22_clipsSortedByCueStart() throws {
        let c3 = Cue(id: 3, videoID: 1, startSec: 3, endSec: 4, text: "üç")
        let r = try XCTUnwrap(build(input(cues: [c1, c3], recordings: [rec(8, cue: 3), r7])))
        XCTAssertEqual(r.plan.clips.map(\.cueID), [1, 3])
        XCTAssertEqual(r.plan.clips.map(\.recordingID), [7, 8])
        XCTAssertEqual(r.plan.clips.map(\.timelineStartSample), [48000, 144000])
    }

    func test_M23_orphanRecordingIgnoredWithWarning() throws {
        let r = try XCTUnwrap(build(input(recordings: [r7, rec(9, cue: 99)])))
        XCTAssertEqual(r.plan.clips.map(\.recordingID), [7])
        XCTAssertEqual(r.warnings, [.orphanRecordingsIgnored(count: 1)])
        XCTAssertEqual(MixPlanWarning.orphanRecordingsIgnored(count: 1).message,
                       "1 kayıt, silinmiş repliğe ait olduğu için atlandı.")
    }

    // MARK: - Scope

    func test_M24_allCuesScopeDucksUnrecordedCues() throws {
        let c5 = Cue(id: 5, videoID: 1, startSec: 5, endSec: 6, text: "beş")
        let all = try XCTUnwrap(build(input(settings: TakeSettings(duckScope: .allCues), cues: [c1, c5])))
        XCTAssertEqual(all.plan.envelope.keyframes, [
            k(24000, 1, eqP), k(48000, 0, nil), k(96000, 0, eqP), k(120000, 1, nil),
            k(216000, 1, eqP), k(240000, 0, nil), k(288000, 0, eqP), k(312000, 1, nil),
        ])
        let recorded = try XCTUnwrap(build(input(settings: TakeSettings(duckScope: .recordedCues), cues: [c1, c5])))
        XCTAssertEqual(recorded.plan.envelope.keyframes,
                       [k(24000, 1, eqP), k(48000, 0, nil), k(96000, 0, eqP), k(120000, 1, nil)])
    }

    func test_M25_hardMuteAlwaysUsesRecordedScope() throws {
        let c5 = Cue(id: 5, videoID: 1, startSec: 5, endSec: 6, text: "beş")
        var s = TakeSettings.pythonParity
        s.duckScope = .allCues
        let r = try XCTUnwrap(build(input(settings: s, cues: [c1, c5])))
        XCTAssertEqual(r.plan.treatment, .hardMute)
        XCTAssertEqual(r.plan.envelope.keyframes, [k(48000, 0, nil), k(96000, 1, nil)])
    }

    // MARK: - Canonical string / hash

    func test_M26_canonicalString() throws {
        let r = try XCTUnwrap(build(input()))
        XCTAssertEqual(r.plan.canonicalString, m26Expected)
    }

    func test_M27_planHashIsStableAndDiscriminating() throws {
        let m2a = try XCTUnwrap(build(input()))
        let m2b = try XCTUnwrap(build(input()))
        let m1 = try XCTUnwrap(build(input(settings: .pythonParity)))
        let m3 = try XCTUnwrap(build(input(settings: TakeSettings(duckDepth: 20))))
        XCTAssertEqual(m2a.plan.planHash, PortableSHA256.hash(m2a.plan.canonicalString).hexString)
        XCTAssertEqual(m2a.plan.planHash, PortableSHA256.hash(m26Expected).hexString)
        XCTAssertEqual(m2a.plan.planHash, m2b.plan.planHash)
        XCTAssertNotEqual(m2a.plan.planHash, m1.plan.planHash)
        XCTAssertNotEqual(m2a.plan.planHash, m3.plan.planHash)
        XCTAssertEqual(m2a.plan.planHash.count, 64)
    }

    func test_extra_canonicalEscapesFileNames() {
        let plan = MixPlan(sampleRate: 48000, durationSamples: 10, hasBedAudio: false, bedGain: 0,
                           treatment: .separated(StemReference(fileName: "b;g%.caf", cueSignature: "s\nx"),
                                                 crossfade: .hardMute),
                           envelope: .identity,
                           clips: [MixClip(recordingID: 1, cueID: 2, fileName: "a;\r.caf", timelineStartSample: 0,
                                           trimStartSamples: 0, trimEndSamples: 0, gain: -0.0)],
                           limiter: nil)
        XCTAssertEqual(plan.canonicalString, [
            "mixplan/1",
            "sr=48000",
            "dur=10",
            "bedAudio=0",
            "bed=0",
            "treat=sep;stem=b%3Bg%25.caf;sig=s%0Ax;L=0;fo=0;fi=0;c=linear;sc=recorded;mr=0",
            "c=1;2;a%3B%0D.caf;0;0;0;0",
            "lim=none",
        ].joined(separator: "\n"))
    }

    func test_extra_takeSettingsDerivedGains() {
        XCTAssertEqual(TakeSettings(bgVolume: -10).bedGain, 0)
        XCTAssertEqual(TakeSettings(dubVolume: 250).dubMasterGain, 2)
        XCTAssertEqual(TakeSettings(duckDepth: 150).duckSettings.level, 1)
        XCTAssertEqual(TakeSettings.pythonParity.duckMode, .mute)
        XCTAssertEqual(Recording(id: 1, takeID: 1, cueID: 1, fileName: "x", volume: 300).gainFactor, 2)
        XCTAssertEqual(LimiterSpec.standard, LimiterSpec(ceiling: 0.85, attackSec: 0.005, releaseSec: 0.050))
    }
}
