import XCTest
import ChoosVoieCore

/// SPEC §7 E1–E24. 48 kHz, D = 10 s (DS = 480000), DuckSettings.default unless noted.
/// Keyframe sample positions independently recomputed as round(sec * 48000).
final class DuckEnvelopeTests: XCTestCase {

    private let eqP = FadeCurve.equalPower
    private let sqrtHalf: Float = 0.70710678

    private func r(_ s: Double, _ e: Double) -> TimeRange { TimeRange(start: s, end: e) }

    private func k(_ s: Int64, _ g: Float, _ c: FadeCurve?) -> GainKeyframe {
        GainKeyframe(sample: s, gain: g, curveToNext: c)
    }

    private func build(_ windows: [TimeRange], _ settings: DuckSettings = .default,
                       duration: Double = 10) -> DuckEnvelope {
        DuckEnvelopeBuilder.build(windows: windows, settings: settings, durationSec: duration, sampleRate: 48_000)
    }

    private func assertGains(
        _ env: DuckEnvelope, _ expected: [(Int64, Float)],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for (n, g) in expected {
            XCTAssertEqual(env.gain(atSample: n), g, accuracy: 1e-6, "gain(\(n))", file: file, line: line)
        }
    }

    private var e1Keyframes: [GainKeyframe] {
        [k(24000, 1, eqP), k(48000, 0, nil), k(96000, 0, eqP), k(120000, 1, nil)]
    }

    // MARK: - Shape & single window

    func test_E1_singleCueKeyframes() {
        XCTAssertEqual(build([r(1, 2)]).keyframes, e1Keyframes)
    }

    func test_E2_equalPowerGainLookup() {
        assertGains(build([r(1, 2)]), [
            (0, 1), (23999, 1), (24000, 1), (36000, sqrtHalf), (48000, 0), (72000, 0),
            (96000, 0), (108000, sqrtHalf), (120000, 1), (479999, 1),
        ])
    }

    func test_E3_linearCurve() {
        let s = DuckSettings(level: 0, fadeOutSec: 0.5, fadeInSec: 0.5, curve: .linear)
        assertGains(build([r(1, 2)], s), [(30000, 0.75), (36000, 0.5), (102000, 0.25), (108000, 0.5)])
    }

    func test_E4_sCurve() {
        let s = DuckSettings(level: 0, fadeOutSec: 0.5, fadeInSec: 0.5, curve: .sCurve)
        assertGains(build([r(1, 2)], s),
                    [(30000, 0.85355339), (36000, 0.5), (102000, 0.14644661), (108000, 0.5)])
    }

    func test_E5_equalPowerQuarterPoints() {
        assertGains(build([r(1, 2)]), [(30000, 0.92387953), (102000, 0.38268343)])
    }

    func test_E6_nonZeroDuckLevel() {
        let s = DuckSettings(level: 0.2, fadeOutSec: 0.5, fadeInSec: 0.5)
        assertGains(build([r(1, 2)], s), [(48000, 0.2), (72000, 0.2), (36000, 0.76568542), (108000, 0.76568542)])
    }

    // MARK: - Merging

    func test_E7_mergeGapBelowFadeSum() {
        let env = build([r(1, 2), r(2.8, 3.5)])
        XCTAssertEqual(env.keyframes, [k(24000, 1, eqP), k(48000, 0, nil), k(168000, 0, eqP), k(192000, 1, nil)])
        XCTAssertEqual(env.gain(atSample: 120000), 0, accuracy: 1e-6)
    }

    func test_E8_gapAboveFadeSumStaysSeparate() {
        let env = build([r(1, 2), r(3.1, 3.5)])
        XCTAssertEqual(env.keyframes, e1Keyframes + [
            k(124800, 1, eqP), k(148800, 0, nil), k(168000, 0, eqP), k(192000, 1, nil),
        ])
        XCTAssertEqual(env.gain(atSample: 122000), 1, accuracy: 1e-6)
    }

    func test_E9_gapExactlyFadeSumStaysSeparateDuplicateSample() {
        let env = build([r(1, 2), r(3.0, 3.5)])
        XCTAssertEqual(env.keyframes, e1Keyframes + [
            k(120000, 1, eqP), k(144000, 0, nil), k(168000, 0, eqP), k(192000, 1, nil),
        ])
        XCTAssertEqual(env.gain(atSample: 120000), 1, accuracy: 1e-6)
        XCTAssertEqual(env.gain(atSample: 132000), sqrtHalf, accuracy: 1e-6)
    }

    // MARK: - Boundaries

    func test_E10_fadeOutClampedAtZero() {
        let env = build([r(0.2, 1.0)])
        XCTAssertEqual(env.keyframes, [k(0, 1, eqP), k(9600, 0, nil), k(48000, 0, eqP), k(72000, 1, nil)])
        assertGains(env, [(0, 1), (4800, sqrtHalf)])
    }

    func test_E11_cueAtZeroHasNoFadeOut() {
        let env = build([r(0.0, 1.0)])
        XCTAssertEqual(env.keyframes, [k(0, 0, nil), k(48000, 0, eqP), k(72000, 1, nil)])
        XCTAssertEqual(env.gain(atSample: 0), 0, accuracy: 1e-6)
    }

    func test_E12_fadeInClampedAtDuration() {
        let env = build([r(9.0, 9.8)])
        XCTAssertEqual(env.keyframes, [k(408000, 1, eqP), k(432000, 0, nil), k(470400, 0, eqP), k(480000, 1, nil)])
        XCTAssertEqual(env.gain(atSample: 475200), sqrtHalf, accuracy: 1e-6)
    }

    func test_E13_cueBeyondDurationEndsDucked() {
        let env = build([r(9.0, 12.0)])
        XCTAssertEqual(env.keyframes, [k(408000, 1, eqP), k(432000, 0, nil), k(480000, 1, nil)])
        XCTAssertEqual(env.gain(atSample: 479999), 0, accuracy: 1e-6)
    }

    func test_E14_cueEntirelyAfterDurationIsIdentity() {
        let env = build([r(11, 12)])
        XCTAssertEqual(env, .identity)
        XCTAssertEqual(env.keyframes, [])
        XCTAssertEqual(env.gain(atSample: 500000), 1)
    }

    // MARK: - Hard mute

    func test_E15_hardMuteIsSampleAccurate() {
        let env = build([r(1, 2)], .hardMute)
        XCTAssertEqual(env.keyframes, [k(48000, 0, nil), k(96000, 1, nil)])
        assertGains(env, [(47999, 1), (48000, 0), (95999, 0), (96000, 1)])
    }

    func test_E16_hardMuteEqualsZeroFadeEqualPower() {
        let a = build([r(1, 2)], .hardMute)
        let b = build([r(1, 2)], DuckSettings(level: 0, fadeOutSec: 0, fadeInSec: 0, curve: .equalPower))
        XCTAssertEqual(a.keyframes, b.keyframes)
    }

    func test_E17_hardMuteTouchingWindowsMerge() {
        XCTAssertEqual(build([r(1, 2), r(2, 3)], .hardMute).keyframes,
                       [k(48000, 0, nil), k(144000, 1, nil)])
    }

    func test_E18_hardMuteTinyGapStaysSeparate() {
        let env = build([r(1, 2), r(2.01, 3)], .hardMute)
        XCTAssertEqual(env.keyframes,
                       [k(48000, 0, nil), k(96000, 1, nil), k(96480, 0, nil), k(144000, 1, nil)])
        assertGains(env, [(96000, 1), (96479, 1), (96480, 0)])
    }

    // MARK: - Ordering / robustness

    func test_E19_overlappingWindowsMerge() {
        XCTAssertEqual(build([r(1, 3), r(2, 4)]).keyframes,
                       [k(24000, 1, eqP), k(48000, 0, nil), k(192000, 0, eqP), k(216000, 1, nil)])
    }

    func test_E20_inputOrderDoesNotMatter() {
        XCTAssertEqual(build([r(2.8, 3.5), r(1, 2)]).keyframes, build([r(1, 2), r(2.8, 3.5)]).keyframes)
    }

    func test_E21_minRecoverMergesShortRecovery() {
        let s = DuckSettings(level: 0, fadeOutSec: 0.5, fadeInSec: 0.5, minRecoverSec: 0.2)
        XCTAssertEqual(build([r(1, 2), r(3.1, 3.5)], s).keyframes,
                       [k(24000, 1, eqP), k(48000, 0, nil), k(168000, 0, eqP), k(192000, 1, nil)])
    }

    func test_E22_invalidWindowsAreSkipped() {
        XCTAssertEqual(build([r(.nan, 2), r(3, 2), r(1, 2)]).keyframes, e1Keyframes)
    }

    func test_E23_fillMatchesGainLookup() {
        let env = build([r(1, 2)])
        var buffer = [Float](repeating: -1, count: 48000)
        env.fill(into: &buffer, startingAt: 24000)
        XCTAssertEqual(buffer.count, 48000)
        for i in stride(from: 0, to: buffer.count, by: 1) where i % 97 == 0 || i == 12000 || i == 47999 {
            XCTAssertEqual(buffer[i], env.gain(atSample: 24000 + Int64(i)), accuracy: 1e-6, "i=\(i)")
        }
        XCTAssertEqual(buffer[0], 1, accuracy: 1e-6)
        XCTAssertEqual(buffer[12000], sqrtHalf, accuracy: 1e-6)
        XCTAssertEqual(buffer[24000], 0, accuracy: 1e-6)

        var empty: [Float] = []
        env.fill(into: &empty, startingAt: 0)
        XCTAssertEqual(empty, [])
    }

    func test_E24_zeroDurationIsIdentity() {
        XCTAssertEqual(build([r(1, 2)], duration: 0), .identity)
        XCTAssertEqual(build([r(1, 2)], duration: .nan), .identity)
    }

    // MARK: - Extras (contract §5.1 / §5.6)

    func test_extra_identityIsUnity() {
        XCTAssertEqual(DuckEnvelope.identity.keyframes, [])
        XCTAssertEqual(DuckEnvelope.identity.gain(atSample: 0), 1)
        XCTAssertEqual(DuckEnvelope.identity.gain(atSample: -5), 1)
    }

    func test_extra_fadeOutShapeEndpointsAndClamping() {
        for c in FadeCurve.allCases {
            XCTAssertEqual(c.fadeOutShape(0), 1, accuracy: 1e-12, "\(c)")
            XCTAssertEqual(c.fadeOutShape(1), 0, accuracy: 1e-12, "\(c)")
            XCTAssertEqual(c.fadeOutShape(-0.5), 1, accuracy: 1e-12, "\(c)")
            XCTAssertEqual(c.fadeOutShape(1.5), 0, accuracy: 1e-12, "\(c)")
        }
        XCTAssertEqual(FadeCurve.equalPower.rawValue, "equal_power")
        XCTAssertEqual(FadeCurve.sCurve.rawValue, "s_curve")
    }

    func test_extra_duckSettingsClamping() {
        let s = DuckSettings(level: 1.5, fadeOutSec: 5, fadeInSec: -1, minRecoverSec: .nan)
        XCTAssertEqual(s.level, 1)
        XCTAssertEqual(s.fadeOutSec, 3)
        XCTAssertEqual(s.fadeInSec, 0)
        XCTAssertEqual(s.minRecoverSec, 0)
        let n = DuckSettings(level: .nan, fadeOutSec: .infinity, fadeInSec: .nan)
        XCTAssertEqual(n.level, 0)
        XCTAssertEqual(n.fadeOutSec, 0)
        XCTAssertEqual(n.fadeInSec, 0)
        XCTAssertEqual(DuckSettings.default,
                       DuckSettings(level: 0, fadeOutSec: 0.5, fadeInSec: 0.5, curve: .equalPower, scope: .recordedCues))
        XCTAssertEqual(DuckSettings.hardMute,
                       DuckSettings(level: 0, fadeOutSec: 0, fadeInSec: 0, curve: .linear, scope: .recordedCues))
    }

    func test_extra_sampleTimeRounding() {
        XCTAssertEqual(SampleTime.samples(fromSeconds: 1, sampleRate: 48_000), 48_000)
        XCTAssertEqual(SampleTime.samples(fromSeconds: 0.25, sampleRate: 2), 1)   // 0.5 → away from zero
        XCTAssertEqual(SampleTime.samples(fromSeconds: -0.25, sampleRate: 2), -1)
        XCTAssertEqual(SampleTime.samples(fromSeconds: .nan, sampleRate: 48_000), 0)
        XCTAssertEqual(SampleTime.samples(fromSeconds: .infinity, sampleRate: 48_000), 0)
        XCTAssertEqual(SampleTime.samples(fromSeconds: 1e300, sampleRate: 48_000), Int64(1) << 62)
        XCTAssertEqual(SampleTime.defaultSampleRate, 48_000)
    }
}
