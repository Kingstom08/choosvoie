# ChoosVoieCore — Uygulama Sözleşmesi (ADR-003)

Platformdan bağımsız saf Swift çekirdeği. Windows, Linux ve macOS'ta `swift test` ile çalışır.
Referans davranış: `app.py` (Python). Tasarım: `docs/ios-swift-mimari.md` §5, §6, §8–§10, §14.

**Paralel çalışma sözleşmesi:** Uygulama mühendisi yalnız `Sources/`, QA mühendisi yalnız `Tests/` altına yazar.
Ortak sözleşme bu belgedeki imzalar ve altın test değerleridir. İmza değişikliği gerekirse önce bu belge güncellenir.

## 1. Kısıtlar

- Yalnız `Foundation` (Linux/Windows'ta swift-corelibs-foundation). **Yasak:** Accelerate, AVFoundation, CryptoKit, Combine, SwiftUI, os/os.Logger, Glibc/Darwin importu. `cos`, `log10`, `pow` Foundation'dan gelir.
- Global değişken durum yok. Değer tipleri, `Sendable`.
- Test çerçevesi **XCTest** (swift-testing'in Windows desteği bilinmiyor).
- Kaynak (resource) dosyası yok; test fikstürleri satır içi string literal.
- Kimlikler `Int64` (SQLite INTEGER PRIMARY KEY uyumu). Dosya adları yol değil, `<uuid>.caf` gibi ad.
- Platform alt sınırı `.iOS(.v17)`, `.macOS(.v14)`.

## 2. Package.swift (birebir)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChoosVoieCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChoosVoieCore", targets: ["ChoosVoieCore"]),
    ],
    targets: [
        .target(
            name: "ChoosVoieCore",
            path: "Sources/ChoosVoieCore"
        ),
        .testTarget(
            name: "ChoosVoieCoreTests",
            dependencies: ["ChoosVoieCore"],
            path: "Tests/ChoosVoieCoreTests"
        ),
    ]
)
```

## 3. Dosya ağacı

```
ios/ChoosVoieCore/
├── Package.swift
├── SPEC.md
├── .gitattributes                 # "* text=auto eol=lf"
├── .gitignore                     # ".build/", ".swiftpm/", "*.xcodeproj"
├── Sources/ChoosVoieCore/
│   ├── Model/        TimeRange, Video, Cue, Take (Take, TakeSettings), Recording (Recording, RecordingSource), DuckTypes (FadeCurve, DuckScope, DuckMode, DuckSettings, BackgroundTreatment, StemReference)
│   ├── Support/      SampleTime, PythonText (internal: strip / splitlines / format yardımcıları)
│   ├── Validation/   CueValidator, BulkShift
│   ├── Segments/     SegmentMerger, CueSignature
│   ├── IO/           CueIO, CueIO+JSON, CueIO+SRT
│   ├── Audio/        DuckEnvelope (GainKeyframe, DuckEnvelope), DuckEnvelopeBuilder, AutoLevel, LevelMeter, TrimDetector
│   ├── Mix/          MixPlan (MixPlan, MixClip, LimiterSpec, canonicalString), MixPlanBuilder
│   ├── Hashing/      PortableSHA256
│   └── Engines/      TranscriptionEngine, SeparationEngine, EntitlementProvider
└── Tests/ChoosVoieCoreTests/
    CueValidatorTests, BulkShiftTests, SegmentMergerTests, CueSignatureTests, PortableSHA256Tests,
    CueIOExportTests, CueIOImportTests, DuckEnvelopeTests, AutoLevelTests, LevelMeterTests,
    MixPlanBuilderTests, EngineProtocolTests
```

Test adları vaka ID'siyle başlar: `test_E7_mergeGapBelowFadeSum`.

## 4. Ortak kurallar (bağlayıcı)

- **Saniye → örnek:** `SampleTime.samples(fromSeconds:sampleRate:)` = `Int64((s * Double(sr)).rounded(.toNearestOrAwayFromZero))`. Sonlu değilse `0`. Çarpım `±2^62` ile kırpılır.
- **SRT, imza v2, ms çevrimi:** `.toNearestOrEven` (Python `round()` banker's rounding, app.py:885).
- **Metin kırpma (Python `str.strip()`):** `unicodeScalars` üzerinde; Unicode `White_Space` özellikli skalarlar + U+001C…U+001F.
- **Sayı biçimi (`%.1f`, `%+.1f`):** `String(format:)`, ondalık ayırıcı ".". Altın testlerde tam-yarı (tie) değer yok.
- **Hatalar:** hepsi `Error, Sendable, Hashable`; `public var message: String` birebir Türkçe mesaj. Testler `Result` eşitliği ve `message` ile yazılır.
- **Hash:** saf Swift SHA-256 (`PortableSHA256`); CryptoKit ile aynı çıktı. Python v1 imzasıyla bayt uyumu gerekmez.

## 5. Public API (birebir imzalar)

### 5.1 Model

```swift
import Foundation

public struct TimeRange: Sendable, Hashable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double)
    public var duration: Double { get }          // end - start
}

public struct Video: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var title: String
    public var fileName: String
    public var durationSec: Double?              // nil/≤0/sonlu değil = bilinmiyor
    public var hasAudio: Bool
    public var isStereo: Bool
    public init(id: Int64, title: String, fileName: String,
                durationSec: Double? = nil, hasAudio: Bool = true, isStereo: Bool = false)
    /// durationSec sonlu ve > 0 ise onu, değilse nil.
    public var knownDurationSec: Double? { get }
}

public struct Cue: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var videoID: Int64
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public init(id: Int64, videoID: Int64, startSec: Double, endSec: Double, text: String)
    public var range: TimeRange { get }
}

public enum FadeCurve: String, Sendable, Hashable, CaseIterable {
    case equalPower = "equal_power"
    case linear = "linear"
    case sCurve = "s_curve"
    /// Fade-out şekli c(u); u önce [0,1]'e kırpılır. c(0)=1, c(1)=0.
    /// linear: 1-u · equalPower: cos(π/2·u) · sCurve: (1+cos(π·u))/2
    public func fadeOutShape(_ u: Double) -> Double
}

public enum DuckScope: String, Sendable, Hashable, CaseIterable {
    case recordedCues = "recorded"
    case allCues = "all"
}

public enum DuckMode: String, Sendable, Hashable, CaseIterable {
    case mute, duck, separated
}

public struct DuckSettings: Sendable, Hashable {
    public static let maxFadeSec: Double = 3.0
    public let level: Float          // [0,1]; sonlu değilse 0
    public let fadeOutSec: Double    // [0,3]; sonlu değilse 0
    public let fadeInSec: Double     // [0,3]; sonlu değilse 0
    public let curve: FadeCurve
    public let scope: DuckScope
    public let minRecoverSec: Double // [0,3]; sonlu değilse 0
    /// Değerleri yukarıdaki aralıklara kırpar.
    public init(level: Float, fadeOutSec: Double, fadeInSec: Double,
                curve: FadeCurve = .equalPower, scope: DuckScope = .recordedCues,
                minRecoverSec: Double = 0)
    public static let `default`: DuckSettings  // (0, 0.5, 0.5, .equalPower, .recordedCues, 0)
    public static let hardMute: DuckSettings   // (0, 0, 0, .linear, .recordedCues, 0)
}

public struct TakeSettings: Sendable, Hashable {
    public var bgVolume: Int        // %0–150 (kullanımda kırpılır)
    public var dubVolume: Int       // %0–200
    public var autoLevel: Bool
    public var duckMode: DuckMode
    public var duckDepth: Int       // 0–100
    public var fadeOutSec: Double
    public var fadeInSec: Double
    public var duckCurve: FadeCurve
    public var duckScope: DuckScope
    public var minRecoverSec: Double
    public init(bgVolume: Int = 100, dubVolume: Int = 100, autoLevel: Bool = false,
                duckMode: DuckMode = .duck, duckDepth: Int = 0,
                fadeOutSec: Double = 0.5, fadeInSec: Double = 0.5,
                duckCurve: FadeCurve = .equalPower, duckScope: DuckScope = .recordedCues,
                minRecoverSec: Double = 0)
    /// Python paritesi: varsayılanlar + duckMode .mute
    public static let pythonParity: TakeSettings
    public var bedGain: Double { get }        // Double(clamp(bgVolume,0,150))/100   (app.py:2673)
    public var dubMasterGain: Double { get }  // Double(clamp(dubVolume,0,200))/100  (app.py:2679)
    /// DuckSettings(level: Float(clamp(duckDepth,0,100))/100, fadeOutSec, fadeInSec, duckCurve, duckScope, minRecoverSec)
    public var duckSettings: DuckSettings { get }
}

public struct Take: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var videoID: Int64
    public var name: String?
    public var settings: TakeSettings
    public init(id: Int64, videoID: Int64, name: String? = nil, settings: TakeSettings = TakeSettings())
}

public enum RecordingSource: String, Sendable, Hashable { case mic, `import` }

public struct Recording: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var takeID: Int64
    public var cueID: Int64
    public var fileName: String
    public var volume: Int              // %0–200
    public var meanDB: Double?
    public var peakDB: Double?
    public var durationSec: Double?
    public var latencyCompSec: Double
    public var sampleRate: Int
    public var source: RecordingSource
    public var trimStartSec: Double
    public var trimEndSec: Double
    public var offsetSec: Double
    public init(id: Int64, takeID: Int64, cueID: Int64, fileName: String,
                volume: Int = 100, meanDB: Double? = nil, peakDB: Double? = nil,
                durationSec: Double? = nil, latencyCompSec: Double = 0,
                sampleRate: Int = 48_000, source: RecordingSource = .mic,
                trimStartSec: Double = 0, trimEndSec: Double = 0, offsetSec: Double = 0)
    public var gainFactor: Double { get }   // Double(clamp(volume,0,200))/100 (app.py:1954)
}

public struct StemReference: Sendable, Hashable {   // URL değil: hash yoldan bağımsız
    public var fileName: String
    public var cueSignature: String
    public init(fileName: String, cueSignature: String)
}

public enum BackgroundTreatment: Sendable, Hashable {
    case hardMute                                        // = duck(0,0,0), kapsam her zaman recorded
    case duck(DuckSettings)
    case separated(StemReference, crossfade: DuckSettings)  // level yok sayılır (0)
}

public enum SampleTime {
    public static let defaultSampleRate: Int = 48_000
    public static func samples(fromSeconds seconds: Double, sampleRate: Int) -> Int64
}
```

### 5.2 CueValidator (app.py:514-546, 620-631)

```swift
public struct ValidatedCueFields: Sendable, Hashable {
    public let startSec: Double
    public let endSec: Double
    public let text: String          // Python strip uygulanmış
}

public enum CueValidationError: Error, Sendable, Hashable {
    case invalidNumber                                   // "Sayısal değer geçersiz"
    case negativeStart                                   // "Başlangıç 0 veya üstü olmalı"
    case endNotAfterStart                                // "Bitiş, başlangıçtan büyük olmalı"
    case emptyText                                       // "Metin boş olamaz"
    case endExceedsDuration(endSec: Double, durationSec: Double)
        // "Bitiş \(%.1f end) sn, video süresini (\(%.1f dur) sn) aşamaz."
    public var message: String { get }
}

public enum CueValidator {
    public static let maxCueSec: Double = 86_400
    public static let durationTolerance: Double = 1e-6
    /// Sıra: sonlu değil → invalidNumber; start>86400 || end>86400 → invalidNumber;
    /// start<0 → negativeStart; end<=start → endNotAfterStart; strip(text) boş → emptyText;
    /// süre biliniyorsa (sonlu ve >0) ve end > süre+1e-6 → endExceedsDuration.
    public static func validate(startSec: Double, endSec: Double, text: String,
                                videoDurationSec: Double? = nil)
        -> Result<ValidatedCueFields, CueValidationError>
    /// Python float(str) paritesi: Python boşlukları kırpılır → Double(_:); nil ise invalidNumber.
    /// İçinde "x"/"X" geçen string reddedilir (hex float, D-7).
    public static func validate(startText: String, endText: String, text: String,
                                videoDurationSec: Double? = nil)
        -> Result<ValidatedCueFields, CueValidationError>
}
```

### 5.3 BulkShift (app.py:773-868)

```swift
public struct BulkShiftResult: Sendable, Hashable {
    public let offsetSec: Double
    public let cues: [Cue]         // startSec'e göre stabil sıralı; id ve text korunur
}

public enum BulkShiftError: Error, Sendable, Hashable {
    case invalidNumber                                    // "Sayısal değer geçersiz"
    case noCues                                           // "Kaydırılacak replik yok"
    case wouldGoBelowZero(minStartSec: Double)
        // "Kaydırma \(%.1f (-minStart + 0.0)) sn'den küçük olamaz: ilk replik 0'ın altına düşer."
    case wouldExceedDuration(maxOffsetSec: Double, durationSec: Double)
        // "Kaydırma \(%+.1f maxOffset) sn'den büyük olamaz: son replik video süresini (\(%.1f dur) sn) aşar."
    case wouldExceedMaxCueTime                            // "Sayısal değer geçersiz"  (D-2)
    case needsConfirmation(recordingCount: Int)
        // "Bu videoda \(n) dublaj kaydı var; tüm replikleri kaydırmak hepsinin senkronunu bozar."
    public var message: String { get }
}

public enum BulkShift {
    public static let tolerance: Double = 1e-6
    /// Sıra: offset sonlu değil → invalidNumber; cues boş → noCues;
    /// minStart+offset < -1e-6 → wouldGoBelowZero(minStart);
    /// süre biliniyorsa ve maxEnd+offset > süre+1e-6 → wouldExceedDuration(süre - maxEnd, süre);
    /// maxEnd+offset > 86400 → wouldExceedMaxCueTime (D-2);
    /// recordingCount>0 && !confirmed → needsConfirmation.
    /// Başarı: her cue start+=offset, end+=offset; sonuç start < 0 ise 0'a çekilir (D-3).
    public static func apply(offsetSec: Double, to cues: [Cue], videoDurationSec: Double?,
                             recordingCount: Int, confirmed: Bool)
        -> Result<BulkShiftResult, BulkShiftError>
}
```

### 5.4 SegmentMerger, CueSignature, PortableSHA256 (app.py:2129-2157)

```swift
public enum SegmentMerger {
    public static let defaultPad: Double = 0.5
    public static let defaultGap: Double = 1.0
    /// s = max(0, start-pad); e = end+pad; süre (sonlu ve >0) ise e = min(e, süre); e > s ise tut.
    /// (s,e) çiftine göre sırala; sıradaki.s - son.e < gap ise son.e = max(son.e, sıradaki.e).
    /// start ya da end sonlu değilse aralık atlanır (D-9).
    public static func merge(_ ranges: [TimeRange], durationSec: Double,
                             pad: Double = defaultPad, gap: Double = defaultGap) -> [TimeRange]
}

public enum CueSignature {
    public static let version: Int = 2
    /// Her aralık: sMs = Int64((start*1000).rounded(.toNearestOrEven)), eMs aynı;
    /// sonlu olmayanlar atlanır; (sMs,eMs) artan sıralanır; her çift "\(sMs)-\(eMs);".
    public static func canonicalString(for ranges: [TimeRange]) -> String
    /// PortableSHA256.hash(canonicalString).hexString
    public static func signature(for ranges: [TimeRange]) -> String
}

public struct SHA256Digest: Sendable, Hashable {
    public let bytes: [UInt8]            // 32 bayt
    public var hexString: String { get } // küçük harf, 64 karakter
}

public enum PortableSHA256 {
    public static func hash(_ bytes: [UInt8]) -> SHA256Digest
    public static func hash(_ string: String) -> SHA256Digest   // UTF-8 baytları
}
```

### 5.5 CueIO (app.py:875-1075)

```swift
public struct CueDraft: Sendable, Hashable {
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public init(startSec: Double, endSec: Double, text: String)
}

public enum CueImportMode: String, Sendable, Hashable { case append, replace }

public enum CueImportError: Error, Sendable, Hashable {
    case fileTooLarge                // "Dosya 1MB sınırını aşıyor"
    case notUTF8                     // "Dosya UTF-8 olarak okunamadı"
    case jsonMissingCuesList         // "JSON içinde 'cues' listesi bulunamadı"
    case unparseable                 // "Dosya ne geçerli JSON ne de SRT olarak ayrıştırılabildi"
    case noValidCues                 // "Geçerli replik bulunamadı"
    case tooManyCues                 // "En fazla 500 replik içe aktarılabilir"
    case replaceBlockedByRecordings  // "Bu videoda kayıtlı dublaj sesleri var; replikleri değiştirmek onları sahipsiz bırakır. Önce dublajları sil ya da 'ekle' modunu kullan."
    public var message: String { get }
}

public struct CueImportPlan: Sendable, Hashable {
    public let mode: CueImportMode
    public let cues: [CueDraft]       // doğrulanmış, dosyadaki sırayla
    public let skippedCount: Int      // JSON: nesne olan eleman sayısı - kabul edilen; SRT: parseSRT sonucu - kabul edilen
    public var successMessage: String { get }   // "\(cues.count) replik içe aktarıldı"
}

public enum CueIO {
    public static let maxImportBytes: Int = 1_048_576
    public static let maxImportCues: Int = 500

    /// JSON v1: Python json.dumps(indent=2, ensure_ascii=False) ile bayt düzeyinde aynı.
    /// Anahtar sırası sabit, sonda newline yok, cue'lar startSec'e göre stabil sıralı.
    public static func exportJSON(videoTitle: String, cues: [Cue],
                                  exportedAt: Date, timeZone: TimeZone) -> String
    /// "yyyy-MM-dd'T'HH:mm:ss" (Gregoryen, saniye kesilir, saat dilimi eki yok)
    public static func exportedAtString(_ date: Date, timeZone: TimeZone) -> String
    /// app.py:936-942. Cue'lar startSec'e göre stabil sıralanır (1..n numaralı). Bloklar "\n" ile birleşir; boş liste ""; metin olduğu gibi.
    public static func exportSRT(cues: [Cue]) -> String
    /// app.py:884-889. ms = max(0, (s*1000).rounded(.toNearestOrEven)); sonlu değilse "00:00:00,000" (D-12)
    public static func srtTimestamp(_ seconds: Double) -> String
    /// app.py:879-881: [^\w\-]+ → "_", baştaki/sondaki "_" kırpılır, boşsa "video"; "\(t)-replikler.\(ext)"
    public static func exportFileName(title: String, ext: String) -> String
    /// app.py:951-972. Ham çıktı: zamanlar doğrulanmamış, metin boş değil. Yalnız boşluktan oluşan satırlar (app.py:957 `if ln.strip() != ""`) indeks/zaman aranmadan önce atılır.
    public static func parseSRT(_ text: String) -> [CueDraft]
    /// Sıra: boyut > 1_048_576 → fileTooLarge; UTF-8 (BOM atılır) geçersiz → notUTF8;
    /// geçerli JSON ama nesne değil ya da "cues" dizi değil → jsonMissingCuesList;
    /// JSON değilse SRT; SRT boşsa → unparseable; temizleme (CueValidator kuralları, süre yok, hatalı satır atlanır);
    /// temiz liste boş → noValidCues; > 500 → tooManyCues;
    /// mode == .replace && existingRecordingCount > 0 → replaceBlockedByRecordings.
    public static func planImport(data: Data, mode: CueImportMode,
                                  existingRecordingCount: Int)
        -> Result<CueImportPlan, CueImportError>
}
```

**Çağıranın yükümlülüğü:** `existingRecordingCount`, planı uygulayan aynı DB işlemi içinde okunmalı (TOCTOU).

**JSON dışa aktarma kaçış kuralları (Python ensure_ascii=False):** `"` → `\"`, `\` → `\\`, `\n` → `\n`, `\r` → `\r`, `\t` → `\t`, `\b` → `\b`, `\f` → `\f`, diğer U+0000–U+001F → `\u00XX` (küçük harf hex), U+007F ve ASCII dışı kaçışsız, `/` kaçışsız. Sayılar Python `repr(float)` gibi: tam sayı değerli Double `1.0` olarak yazılır (`1` değil), diğerleri en kısa gidiş-dönüş gösterimi (Swift `"\(Double)"` çıktısıyla çoğu durumda aynı; `1e-05` gibi üstel biçimler altın testlerde yok). `version` ve `cue_count` tamsayı.

**JSON içe aktarma:** internal `JSONValue` enum'u (null, Bool, Double, String, dizi, nesne) ile `JSONDecoder`. Sayıya zorlama: Double olduğu gibi; Bool → 1.0/0.0; String → Python kırpma + `Double(_:)`, "x"/"X" içeriyorsa red; null/dizi/nesne → satır atlanır. Metin string değilse satır atlanır (D-5).

**SRT ayrıştırma:** Bloklar `\r?\n\r?\n+` regex'iyle bölünür (NSRegularExpression ya da `unicodeScalars` taraması; Swift `Character` KULLANMA — `"\r\n"` tek grapheme). Satırlar Python `splitlines` sınırlarıyla: \n, \r, \r\n, \v, \f, \x1c, \x1d, \x1e, \x85, U+2028, U+2029. İndeks satırı `^\d+$`. Zaman regex'i (search): `(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)`. Saniye `Double(h*3600+m*60+s) + Double(ms3)/1000.0`; `ms3` = ms grubu sağdan "0" ile 3 haneye doldurulup ilk 3 hanesi. Grup `Int` olamazsa blok atlanır (D-8). Python mantığı: blok satırlarında zaman satırı bulunur (ilk satır indeks ise ikinci satır, değilse ilk satır zaman olmalı; regex eşleşmezse blok atlanır); metin = `strip(" ".join(zaman satırından sonraki satırlar))`, satırlar tek tek kırpılmaz; metin boşsa blok atlanır.

### 5.6 DuckEnvelope ve DuckEnvelopeBuilder (§5)

```swift
public struct GainKeyframe: Sendable, Hashable {
    public let sample: Int64
    public let gain: Float
    public let curveToNext: FadeCurve?   // nil = sonraki keyframe'e kadar sabit
    public init(sample: Int64, gain: Float, curveToNext: FadeCurve?)
}

public struct DuckEnvelope: Sendable, Hashable {
    public let keyframes: [GainKeyframe]   // sample azalmayan sırada
    public init(keyframes: [GainKeyframe])
    public static let identity: DuckEnvelope   // keyframes: []
    /// n < ilk keyframe → 1.0. k = sample <= n olan SON keyframe.
    /// k sonuncuysa ya da curveToNext nil ise → k.gain.
    /// Değilse p0=k.sample, p1=next.sample, u=Double(n-p0)/Double(p1-p0), g0=k.gain, g1=next.gain:
    ///   g0 > g1: g1 + (g0-g1)*c(u)  ·  g0 < g1: g0 + (g1-g0)*c(1-u)  ·  eşitse g0
    /// Hesap Double, sonuç Float.
    public func gain(atSample n: Int64) -> Float
    /// buffer[i] = gain(atSample: startSample + Int64(i)) (tolerans 1e-6)
    public func fill(into buffer: inout [Float], startingAt startSample: Int64)
}

public enum DuckEnvelopeBuilder {
    /// DS = samples(durationSec); DS <= 0 ise .identity.
    /// Her pencere: start ya da end sonlu değilse atla; sS = max(0, samples(start)), sE = min(DS, samples(end)); sE <= sS ise atla.
    /// foS, fiS, mrS = samples(fadeOut / fadeIn / minRecover).
    /// (sS,sE)'ye göre sırala; gap = next.sS - cur.sE; gap <= 0 || gap < foS+fiS+mrS ise cur.sE = max(cur.sE, next.sE), değilse pencereyi kapat.
    /// Birleşik her pencere: sA = max(0, sS-foS), sB = min(DS, sE+fiS), L = settings.level:
    ///   sA < sS ise (sA, 1, curve) ekle
    ///   (sS, L, nil) ekle
    ///   sB > sE ise (sE, L, curve), (sB, 1, nil) ekle; değilse (sE, 1, nil) ekle
    ///   (sE == DS ve sB == sE durumunda son keyframe (DS, 1, nil) olur; gain(DS-1) = L)
    public static func build(windows: [TimeRange], settings: DuckSettings,
                             durationSec: Double,
                             sampleRate: Int = SampleTime.defaultSampleRate) -> DuckEnvelope
}
```

### 5.7 AutoLevel, LevelMeter, TrimDetector (app.py:1874-1908)

```swift
public enum AutoLevel {
    public static let targetDB: Double = -20.0
    public static let maxBoostDB: Double = 15.0
    public static let maxCutDB: Double = -6.0
    public static let peakCeilDB: Double = -1.0
    public static let silenceFloorDB: Double = -45.0
    /// mean nil ya da <= -45 → 1.0; gDB = max(-6, min(15, -20 - mean)); peak varsa gDB = min(gDB, -1 - peak); dönüş 10^(gDB/20)
    public static func gain(meanDB: Double?, peakDB: Double?) -> Double
}

public struct LevelMeasurement: Sendable, Hashable {
    public let meanDB: Double              // 10*log10(Σx²/n), tutulan örneklerde
    public let peakDB: Double              // 20*log10(max|x|), tutulan örneklerde
    public let measuredSampleCount: Int
}

public enum LevelMeter {
    public static let windowSec: Double = 0.020
    public static let silenceThresholdDB: Double = -50.0   // pencere ortalama karesi < 1e-5 ise sessiz
    public static let minSilenceSec: Double = 0.2
    /// W = max(1, samples(0.02)); son kısmi pencere de pencere. Toplama Double.
    /// 1) Baştaki sessiz pencerelerin tamamı atılır (uzunluk fark etmez).
    /// 2) Kalan sessiz pencere dizilerinden (sondaki dahil) toplam örnek sayısı >= samples(0.2) olanlar atılır; kısalar tutulur.
    /// Tutulan örnek yoksa nil.
    public static func measure(samples: [Float], sampleRate: Int) -> LevelMeasurement?
}

public struct TrimResult: Sendable, Hashable {
    public let trimStartSec: Double
    public let trimEndSec: Double
}

public enum TrimDetector {
    /// LevelMeter pencere/eşik değerleri. Baştaki ve sondaki sessiz dizi >= samples(0.2) ise uzunluk/sampleRate, değilse 0. Tamamen sessiz ya da boşsa nil.
    public static func detect(samples: [Float], sampleRate: Int) -> TrimResult?
}
```

### 5.8 MixPlan ve MixPlanBuilder (app.py:2570-2784)

```swift
public struct LimiterSpec: Sendable, Hashable {
    public let ceiling: Float        // doğrusal
    public let attackSec: Double
    public let releaseSec: Double
    public init(ceiling: Float, attackSec: Double, releaseSec: Double)
    public static let standard: LimiterSpec   // (0.85, 0.005, 0.050)  app.py:2711
}

public struct MixClip: Sendable, Hashable {
    public let recordingID: Int64
    public let cueID: Int64
    public let fileName: String
    public let timelineStartSample: Int64   // >= 0
    public let trimStartSamples: Int64      // >= 0
    public let trimEndSamples: Int64        // >= 0
    public let gain: Float                  // dubMaster × recVol × auto
    public init(recordingID: Int64, cueID: Int64, fileName: String,
                timelineStartSample: Int64, trimStartSamples: Int64,
                trimEndSamples: Int64, gain: Float)
}

public struct MixPlan: Sendable, Hashable {
    public let sampleRate: Int
    public let durationSamples: Int64
    public let hasBedAudio: Bool
    public let bedGain: Float
    public let treatment: BackgroundTreatment
    public let envelope: DuckEnvelope
    public let clips: [MixClip]
    public let limiter: LimiterSpec?
    public init(sampleRate: Int, durationSamples: Int64, hasBedAudio: Bool, bedGain: Float,
                treatment: BackgroundTreatment, envelope: DuckEnvelope,
                clips: [MixClip], limiter: LimiterSpec?)
    /// Kanonik biçim (aşağıda); "\n" ile birleşir, sonda newline yok.
    public var canonicalString: String { get }
    /// PortableSHA256.hash(canonicalString).hexString  (takes.rendered_plan_hash)
    public var planHash: String { get }
}

public enum MixPlanWarning: Sendable, Hashable {
    case separatedUnavailableUsedDuck     // "Ayrılmış arka plan kullanılamadı; yumuşak geçiş uygulandı."
    case orphanRecordingsIgnored(count: Int)   // "\(n) kayıt, silinmiş repliğe ait olduğu için atlandı."
    public var message: String { get }
}

public enum MixPlanError: Error, Sendable, Hashable {
    case invalidSampleRate                // "Geçersiz örnekleme hızı"
    case unknownDuration                  // "Video süresi bilinmiyor; montaj yapılamadı."
    case noRecordings                     // "En az bir replik kaydedilmeli"  (app.py:2598)
    case invalidCueTime(startSec: Double) // "Başlangıcı \(%.1f) sn olan repliğin zaman bilgisi geçersiz, montaj yapılamadı. Lütfen bu repliği düzenleyip tekrar deneyin."  (app.py:2618-2621)
    public var message: String { get }
}

public struct MixPlanInput: Sendable {
    public var take: Take
    public var cues: [Cue]                // videonun tüm cue'ları
    public var recordings: [Recording]
    public var videoDurationSec: Double
    public var hasAudio: Bool
    public var stem: StemReference?
    public var sampleRate: Int
    public init(take: Take, cues: [Cue], recordings: [Recording], videoDurationSec: Double,
                hasAudio: Bool, stem: StemReference? = nil,
                sampleRate: Int = SampleTime.defaultSampleRate)
}

public struct MixPlanBuildResult: Sendable, Hashable {
    public let plan: MixPlan
    public let warnings: [MixPlanWarning]   // hash'e girmez
}

public enum MixPlanBuilder {
    public static func build(_ input: MixPlanInput) -> Result<MixPlanBuildResult, MixPlanError>
}
```

**`MixPlanBuilder.build` algoritması:**
1. `sampleRate <= 0` → `invalidSampleRate`. Süre sonlu değil ya da ≤ 0 → `unknownDuration`.
2. `recs = recordings.filter { $0.takeID == take.id }`. Cue'su `cues` içinde olmayanlar atılır; sayı > 0 ise `orphanRecordingsIgnored(count)` uyarısı.
3. `recs` boş → `noRecordings`.
4. Girdi sırasıyla (sıralamadan önce) her kaydın cue'su: start ya da end sonlu değil veya > 86400 ise ilk ihlalde `invalidCueTime(startSec:)`.
5. Kayıtlar `(cue.startSec, recording.id)` sırasına dizilir.
6. Treatment: `.mute` → `.hardMute`; `.duck` → `.duck(settings.duckSettings)`; `.separated` → `stem != nil && hasAudio` ise `.separated(stem, crossfade: duckSettings (level 0'a ayarlı; planHash duckDepth'ten bağımsız))`, değilse `.duck(duckSettings)` + `separatedUnavailableUsedDuck`.
7. Zarf ayarı: hardMute → `DuckSettings.hardMute`; duck(s) → `s`; separated(_, s) → `s` ama level 0. Pencereler: hardMute ya da kapsam `.recordedCues` → kayıtlı cue'ların aralıkları (benzersiz); `.allCues` → tüm `cues` aralıkları. `DuckEnvelopeBuilder.build(...)`.
8. Her klip: `g = dubMasterGain × gainFactor × (autoLevel ? AutoLevel.gain(meanDB, peakDB) : 1)` (Double). Sonlu olmayan offset/latency/trim = 0; `trimStartSec`/`trimEndSec` bir kez `max(0, sonlu-ya-da-0)` ile kırpılır ve hem start hem trimS/trimE hesabında bu değer kullanılır (klibi kaydırmak için `offsetSec`). `start = samples(cue.startSec + offsetSec - latencyCompSec + trimStartSec)` (soldan sağa Double toplama). `trimS = samples(trimStartSec)`, `trimE = samples(trimEndSec)`. `start < 0` ise `trimS += -start` (doygun toplama, ±2^62'ye kırpılır; taşma tuzağı yok), `start = 0`. Trim ve start değerleri plan `sampleRate` cinsindendir; renderer kayıtları trim uygulamadan önce `plan.sampleRate`'e yeniden örneklemelidir.
9. `maxGain = max(1.0, bedGain, tüm g)`. Limiter `.standard`: `maxGain > 1 + 1e-6` VEYA treatment `.duck(s)` ve `s.level > 0` VEYA treatment `.separated`. Aksi `nil`.
10. `bedGain = Float(settings.bedGain)`, `durationSamples = samples(videoDurationSec)`, `hasBedAudio = hasAudio`.

**Kanonik biçim:**
- `hexF(x) = String((x == 0 ? 0 : x).bitPattern, radix: 16)` (Float, -0 → 0). `hexD` aynı kural Double için.
- `esc(s)`: önce `%`→`%25`, sonra `;`→`%3B`, `\n`→`%0A`, `\r`→`%0D`.
- `duckCanon(s) = "L=\(hexF level);fo=\(hexD);fi=\(hexD);c=\(curve.rawValue);sc=\(scope.rawValue);mr=\(hexD)"`

```
mixplan/1
sr=<sampleRate>
dur=<durationSamples>
bedAudio=<1|0>
bed=<hexF bedGain>
treat=mute | treat=duck;<duckCanon> | treat=sep;stem=<esc fileName>;sig=<esc cueSignature>;<duckCanon>
k=<sample>;<hexF gain>;<curve.rawValue | ->        (her keyframe, sırayla)
c=<recordingID>;<cueID>;<esc fileName>;<timelineStartSample>;<trimStartSamples>;<trimEndSamples>;<hexF gain>   (her klip)
lim=none | lim=<hexF ceiling>;<hexD attackSec>;<hexD releaseSec>
```

### 5.9 Motor protokolleri (yalnız imzalar)

```swift
public struct TranscriptWord: Sendable, Hashable {
    public var text: String; public var range: TimeRange
    public init(text: String, range: TimeRange)
}
public struct TranscriptSegment: Sendable, Hashable {
    public var range: TimeRange; public var text: String; public var words: [TranscriptWord]?
    public init(range: TimeRange, text: String, words: [TranscriptWord]? = nil)
}
public enum TranscriptionEvent: Sendable { case progress(Double); case segment(TranscriptSegment) }
public enum EngineAvailability: Sendable, Hashable { case ready; case needsDownload(bytes: Int64?); case unsupported }

public protocol TranscriptionEngine: Sendable {
    var id: String { get }
    var requiresNetwork: Bool { get }
    func availability(for locale: Locale) async -> EngineAvailability
    func transcribe(audio: URL, range: TimeRange?, locale: Locale)
        -> AsyncThrowingStream<TranscriptionEvent, any Error>
}

public enum SeparationMethod: String, Sendable, Hashable { case light, companion, cloud, coreml }
public struct AudioTrackInfo: Sendable, Hashable {
    public var channelCount: Int; public var sampleRate: Double; public var durationSec: Double
    public init(channelCount: Int, sampleRate: Double, durationSec: Double)
}
public protocol SeparationEngine: Sendable {
    var method: SeparationMethod { get }
    var requiresNetwork: Bool { get }
    func canHandle(_ info: AudioTrackInfo) async -> Bool
    func separateSegment(source: URL, range: TimeRange, into output: URL) async throws
}

public enum Tier: String, Sendable, Hashable { case normal, pro }
public protocol EntitlementProvider: Sendable { func currentTier() async -> Tier }
```

## 6. Python'dan bilinçli sapmalar

| ID | Sapma | Gerekçe |
|---|---|---|
| D-1 | Validator süre kontrolünü süre verildiğinde her zaman yapar (Python yalnız güncellemede) | tutarlılık |
| D-2 | BulkShift: maxEnd+offset > 86400 reddedilir | Python render'da reddediyor (2617) |
| D-3 | BulkShift: −1e-6…0 sonuç start'ı 0'a çekilir | validator sonra reddederdi |
| D-4 | BulkShift mesajı `-0.0` yerine `0.0` | kozmetik |
| D-5 | İçe aktarmada metin string değilse satır atlanır | Python istisna fırlatıyor (1036) |
| D-6 | JSON'da NaN/Infinity/1e400 dosyayı JSON olarak geçersiz kılar | JSONDecoder kabul etmez |
| D-7 | Sayısal string: hex reddedilir, `1_000` kabul edilmez | uç durum |
| D-8 | SRT'de ASCII dışı rakam grubu bloğu atlatır | Python int() Unicode rakam kabul eder |
| D-9 | SegmentMerger sonlu olmayan aralıkları atlar | fail-safe |
| D-10 | Klip konumu örnek cinsinden, yarıda sıfırdan uzağa yuvarlanır | fark ≤ 0,5 ms |
| D-11 | Sert susturma örnek hassasiyetinde | ffmpeg çerçeve düzeyi |
| D-12 | srtTimestamp sonlu değilse `00:00:00,000` | Python fırlatır |
| D-13 | Limiter koşulu genişledi | §5 |
| D-14 | hardMute kapsamı her zaman recorded | Python paritesi (2684) |
| D-15 | AutoLevel: sonlu olmayan ortalama → 1.0; tepe +inf → artış yok (`min(gDB, 0)`); tepe NaN/-inf yok sayılır | Python'da tanımsız/uç durum |
| D-16 | JSON dışa aktarmada sonlu olmayan double `0.0` yazılır; \|v\| ≥ 1e16 Python repr üstel biçimiyle yazılır (`1e+16`) | geçerli JSON; Python repr paritesi |
| D-17 | MixPlanBuilder `invalidCueTime`'ı girdi sırasında raporlar (Python start sırasında) | yalnız hangi cue'nun raporlandığı değişir |

## 7. Altın test seti

Tolerans: Float kazanç 1e-6, dB 1e-9, saniye 1e-9. "→ ok(...)" başarı, "→ X" hata.

### V. CueValidator

| ID | Girdi (start, end, text, süre) | Beklenen |
|---|---|---|
| V1 | 1.0, 2.0, "  Merhaba ", nil | ok(1.0, 2.0, "Merhaba") |
| V2 | 0, 0.5, "a", nil | ok |
| V3 | .nan, 1, "a" | invalidNumber, "Sayısal değer geçersiz" |
| V4 | 0, .infinity, "a" | invalidNumber |
| V5 | 86400, 86400.5, "a" | invalidNumber |
| V6 | 86399, 86400, "a" | ok |
| V7 | -0.1, 1, "a" | negativeStart, "Başlangıç 0 veya üstü olmalı" |
| V8 | 2, 2, "a" | endNotAfterStart, "Bitiş, başlangıçtan büyük olmalı" |
| V9 | 3, 2, "a" | endNotAfterStart |
| V10 | 1, 2, "   " | emptyText, "Metin boş olamaz" |
| V11 | -1, -2, "" | negativeStart |
| V12 | .nan, 2, "" | invalidNumber |
| V13 | 1, 10.0000005, "a", 10 | ok |
| V14 | 1, 10.5, "a", 10 | endExceedsDuration, "Bitiş 10.5 sn, video süresini (10.0 sn) aşamaz." |
| V15 | 1, 10.5, "a", 0 | ok |
| V16 | 1, 10.5, "a", nil | ok |
| V17 | 1, 2, "\u{1F}x\u{A0}" | ok, text "x" |
| V18 | startText "1,5", "2", "a" | invalidNumber |
| V19 | startText " 1.5 ", "2", "a" | ok(1.5, 2.0, "a") |
| V20 | startText "0x10", "20", "a" | invalidNumber |
| V21 | startText "abc", "2", "a" | invalidNumber |

### B. BulkShift — cue'lar c1 [1–2], c2 [3–4]; süre 10; kayıt 0

| ID | Girdi | Beklenen |
|---|---|---|
| B1 | offset 0.5 | ok: [1.5–2.5], [3.5–4.5], id'ler korunur |
| B2 | -1.0 | ok: [0–1], [2–3] |
| B3 | -1.5 | wouldGoBelowZero(1.0), "Kaydırma -1.0 sn'den küçük olamaz: ilk replik 0'ın altına düşer." |
| B4 | 6.0 | ok |
| B5 | 6.5 | wouldExceedDuration(6.0, 10.0), "Kaydırma +6.0 sn'den büyük olamaz: son replik video süresini (10.0 sn) aşar." |
| B6 | süre nil, 100 | ok |
| B7 | .nan / .infinity | invalidNumber |
| B8 | cue'lar [], 1 | noCues, "Kaydırılacak replik yok" |
| B9 | cue'lar [], .nan | invalidNumber |
| B10 | kayıt 3, onay false, 0.5 | needsConfirmation(3), "Bu videoda 3 dublaj kaydı var; tüm replikleri kaydırmak hepsinin senkronunu bozar." |
| B11 | kayıt 3, onay true | ok |
| B12 | kayıt 3, onay false, -1.5 | wouldGoBelowZero |
| B13 | cue'lar [0–1], -0.5 | wouldGoBelowZero(0), "Kaydırma 0.0 sn'den küçük olamaz: ilk replik 0'ın altına düşer." |
| B14 | cue'lar [1–2], -1.0000005 | ok; start == 0, end ≈ 0.9999995 |
| B15 | cue'lar [86000–86300], süre nil, 200 | wouldExceedMaxCueTime |
| B16 | sıra [c2, c1], 0 | sonuç [c1, c2] |

### G. SegmentMerger (pad 0.5, gap 1.0)

| ID | Girdi, süre | Beklenen |
|---|---|---|
| G1 | [1–2], 10 | [0.5–2.5] |
| G2 | [1–2], [2.8–3.5], 10 | [0.5–4.0] |
| G3 | [1–2], [4.1–5], 10 | [0.5–2.5], [3.6–5.5] |
| G4 | [1–2], [3.9–5], 10 | [0.5–5.5] |
| G5 | [1–2], [4.0–5], 10 | [0.5–2.5], [3.5–5.5] |
| G6 | [0.2–1.0], 10 | [0.0–1.5] |
| G7 | [9.8–10], 10 | [9.3–10.0] |
| G8 | [9.8–10], 0 | [9.3–10.5] |
| G9 | [10.6–11], 10 | [] |
| G10 | [5–6], [1–2], 10 | [0.5–2.5], [4.5–6.5] |
| G11 | [1–10], [2–3], 20 | [0.5–10.5] |
| G12 | [.nan–2], [1–2], 10 | [0.5–2.5] |

### H. Hash ve imza

| ID | Girdi | Beklenen |
|---|---|---|
| H1 | SHA256("") | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| H2 | "abc" | ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad |
| H3 | "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" | 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1 |
| H4 | "a" × 1 000 000 | cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0 |
| H5 | "The quick brown fox jumps over the lazy dog" | d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592 |
| H6 | canonicalString([2.8–3.5], [1.0–2.0]) | "1000-2000;2800-3500;" |
| H7 | signature(aynı küme, farklı sıra) | eşit; == PortableSHA256.hash("1000-2000;2800-3500;").hexString |
| H8 | [0.0625–1.0] | "62-1000;" |
| H9 | [.nan–1], [1–2] | "1000-2000;" |

### S. SRT zaman damgası

| ID | Girdi | Beklenen |
|---|---|---|
| S1 | 0 | "00:00:00,000" |
| S2 | 3661.5 | "01:01:01,500" |
| S3 | 0.0625 | "00:00:00,062" |
| S4 | 0.1875 | "00:00:00,188" |
| S5 | -1 | "00:00:00,000" |
| S6 | 86400 | "24:00:00,000" |
| S7 | 360000 | "100:00:00,000" |
| S8 | .nan | "00:00:00,000" |

### P. SRT ayrıştırma — çıktı [(start, end, text)]

| ID | Girdi (Swift literal) | Beklenen |
|---|---|---|
| P1 | "1\r\n00:00:01,000 --> 00:00:02,500\r\nMerhaba\r\ndünya\r\n\r\n2\r\n00:00:03.25 --> 00:00:04.5\r\nİkinci\r\n" | [(1.0, 2.5, "Merhaba dünya"), (3.25, 4.5, "İkinci")] |
| P2 | "00:00:05,000 --> 00:00:06,000\nNo index\n" | [(5, 6, "No index")] |
| P3 | "1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03,000 --> 00:00:04,000\nB" | [(3, 4, "B")] |
| P4 | "1\n\nhello\n\n2\n00:00:01,000 --> 00:00:02,000\nX" | [(1, 2, "X")] |
| P5 | "00:00:01,2345 --> 00:00:02,0\nA" | [(1.234, 2.0, "A")] |
| P6 | "01:02:03,004 --> 01:02:04,000\nA" | start == Double(3723) + 4/1000.0 |
| P7 | "00:00:01,000 --> 00:00:02,000 X1:40 X2:600\nA" | [(1, 2, "A")] |
| P8 | "00:00:05,000 --> 00:00:04,000\nA" | [(5, 4, "A")] |
| P9 | "1\n00:00:01,000 --> 00:00:02,000\n  a  \n  b  " | [(1, 2, "a     b")] (5 boşluk) |
| P10 | "1\n00:00:01,000 --> 00:00:02,000\nA\n \n2\n00:00:03,000 --> 00:00:04,000\nB" | [(1, 2, "A 2 00:00:03,000 --> 00:00:04,000 B")] |
| P11 | "" ve "   \n\n" | [] |

### J/F. Dışa aktarma

Fikstür: başlık `Demo "1"`, cue'lar `(1.0, 2.5, "Merhaba")`, `(3.25, 4.0, "Satır\nİki")` (gerçek newline), `exportedAt = Date(timeIntervalSince1970: 1_763_202_030)`.

**J1** `TimeZone(secondsFromGMT: 0)` (sonda newline yok):

```
{
  "app": "choos-voie",
  "version": 1,
  "video_title": "Demo \"1\"",
  "exported_at": "2025-11-15T10:20:30",
  "cue_count": 2,
  "cues": [
    {
      "start_sec": 1.0,
      "end_sec": 2.5,
      "text": "Merhaba"
    },
    {
      "start_sec": 3.25,
      "end_sec": 4.0,
      "text": "Satır\nİki"
    }
  ]
}
```

- **J2** `TimeZone(secondsFromGMT: 10800)` → `"2025-11-15T13:20:30"`; `1_763_202_030.9` de `:30`.
- **J3** Boş liste: `"cue_count": 0,` ve `"cues": []`.
- **J4** Metin `"a\\b\t\u{1}\u{7F}"` → JSON'da `"a\\\\b\\t\\u0001` + ham U+007F + `"` (Swift literal anlamında: ters bölü kaçışlı, tab `\t`, U+0001 `\u0001`, U+007F ham).
- **J5** SRT: `"1\n00:00:01,000 --> 00:00:02,500\nMerhaba\n\n2\n00:00:03,250 --> 00:00:04,000\nSatır\nİki\n"`; boş liste `""`.
- **J6** Girdi sırası ters → çıktı J1 ile aynı.
- **J7** `planImport(Data(exportJSON(...).utf8), .append, 0)` → `[(1.0, 2.5, "Merhaba"), (3.25, 4.0, "Satır\nİki")]`.
- **F1** `exportFileName("Benim Videom: Bölüm 1!", "json")` → `"Benim_Videom_Bölüm_1-replikler.json"`
- **F2** `"!!!"`, `"srt"` → `"video-replikler.srt"`
- **F3** `"a__b"` → `"a__b-replikler.json"`
- **F4** `"-x-"` → `"-x--replikler.json"`

### I. İçe aktarma planı

| ID | Girdi | Beklenen |
|---|---|---|
| I1 | `{"app":"choos-voie","version":1,"cues":[{"start_sec":1.0,"end_sec":2.5,"text":" Merhaba "},{"start_sec":3,"end_sec":3,"text":"x"},{"start_sec":"4.5","end_sec":5,"text":"Dört"},"junk",{"start_sec":null,"end_sec":6,"text":"y"}]}`, append | ok: [(1.0, 2.5, "Merhaba"), (4.5, 5.0, "Dört")], skippedCount 2, "2 replik içe aktarıldı" |
| I2 | `{"cues":"x"}` | jsonMissingCuesList |
| I3 | `[1,2]` | jsonMissingCuesList |
| I4 | `{"foo":1}` | jsonMissingCuesList |
| I5 | `{"cues":[{"start_sec":true,"end_sec":2,"text":"a"}]}` | ok [(1.0, 2.0, "a")] |
| I6 | `{"cues":[{"start_sec":1,"end_sec":2,"text":5}]}` | noValidCues |
| I7 | EF BB BF + I1 | I1 ile aynı |
| I8 | bayt [0xFF, 0xFE, 0x41] | notUTF8, "Dosya UTF-8 olarak okunamadı" |
| I9 | "hello" | unparseable |
| I10 | 1_048_577 bayt | fileTooLarge |
| I11 | tam 1_048_576 bayt, geçerli SRT + boşluk dolgusu | ok |
| I12 | 501 geçerli cue | tooManyCues |
| I13 | 500 geçerli + 1 geçersiz | ok, 500 cue, skippedCount 1 |
| I14 | geçerli JSON, replace, kayıt 2 | replaceBlockedByRecordings (tam mesaj) |
| I15 | aynısı, append, kayıt 2 | ok |
| I16 | replace, kayıt 2, tüm cue'lar geçersiz | noValidCues |
| I17 | P1 metni, append | ok 2 cue |
| I18 | `{"cues":[{"start_sec":0,"end_sec":90000,"text":"a"},{"start_sec":-1,"end_sec":1,"text":"b"},{"start_sec":0,"end_sec":1,"text":"   "}]}` | noValidCues |
| I19 | cue end 999 | ok (içe aktarmada süre kontrolü yok) |

### E. DuckEnvelope — 48 kHz, D = 10 sn (DS = 480000), `DuckSettings.default`

| ID | Girdi | Beklenen |
|---|---|---|
| E1 | cue 1–2 | [(24000, 1, eqP), (48000, 0, nil), (96000, 0, eqP), (120000, 1, nil)] |
| E2 | E1 gain(n) | 0→1; 23999→1; 24000→1; 36000→0.70710678; 48000→0; 72000→0; 96000→0; 108000→0.70710678; 120000→1; 479999→1 |
| E3 | E1, linear | 30000→0.75; 36000→0.5; 102000→0.25; 108000→0.5 |
| E4 | E1, sCurve | 30000→0.85355339; 36000→0.5; 102000→0.14644661; 108000→0.5 |
| E5 | E1, equalPower | 30000→0.92387953; 102000→0.38268343 |
| E6 | E1, level 0.2 | 48000→0.2; 36000→0.76568542; 108000→0.76568542 |
| E7 | 1–2 + 2.8–3.5 | [(24000, 1, eqP), (48000, 0, nil), (168000, 0, eqP), (192000, 1, nil)]; gain(120000) = 0 |
| E8 | 1–2 + 3.1–3.5 | E1 + [(124800, 1, eqP), (148800, 0, nil), (168000, 0, eqP), (192000, 1, nil)] |
| E9 | 1–2 + 3.0–3.5 | E1 + [(120000, 1, eqP), (144000, 0, nil), (168000, 0, eqP), (192000, 1, nil)]; gain(120000) = 1 |
| E10 | 0.2–1.0 | [(0, 1, eqP), (9600, 0, nil), (48000, 0, eqP), (72000, 1, nil)]; gain(0)=1; gain(4800)=0.70710678 |
| E11 | 0.0–1.0 | [(0, 0, nil), (48000, 0, eqP), (72000, 1, nil)]; gain(0) = 0 |
| E12 | 9.0–9.8 | [(408000, 1, eqP), (432000, 0, nil), (470400, 0, eqP), (480000, 1, nil)]; gain(475200) = 0.70710678 |
| E13 | 9.0–12.0 | [(408000, 1, eqP), (432000, 0, nil), (480000, 1, nil)]; gain(479999) = 0 |
| E14 | 11–12 | identity; gain(500000) = 1 |
| E15 | .hardMute, 1–2 | [(48000, 0, nil), (96000, 1, nil)]; 47999→1, 48000→0, 95999→0, 96000→1 |
| E16 | E15 == DuckSettings(level 0, fo 0, fi 0, .equalPower) ile kurulan | keyframe'ler eşit |
| E17 | hardMute, 1–2 + 2–3 | [(48000, 0, nil), (144000, 1, nil)] |
| E18 | hardMute, 1–2 + 2.01–3 | [(48000, 0, nil), (96000, 1, nil), (96480, 0, nil), (144000, 1, nil)] |
| E19 | 1–3 + 2–4 | [(24000, 1, eqP), (48000, 0, nil), (192000, 0, eqP), (216000, 1, nil)] |
| E20 | E7 ters sıra | E7 ile aynı |
| E21 | minRecover 0.2, 1–2 + 3.1–3.5 | [(24000, 1, eqP), (48000, 0, nil), (168000, 0, eqP), (192000, 1, nil)] |
| E22 | [.nan–2], [3–2], 1–2 | E1 ile aynı |
| E23 | fill 48000 eleman, start 24000, E1 | buffer[i] == gain(24000+i) ±1e-6; buffer[12000] = 0.70710678; 0 elemanlı buffer'da işlem yok |
| E24 | durationSec 0 | identity |

### A. AutoLevel (göreli tolerans 1e-12)

| ID | mean, peak | Beklenen |
|---|---|---|
| A1 | nil, nil | 1.0 |
| A2 | -45, -3 | 1.0 |
| A3 | -44.9, nil | 5.623413251903491 |
| A4 | -40, nil | 5.623413251903491 |
| A5 | -30, -10 | 2.8183829312644537 |
| A6 | -30, -20 | 3.1622776601683795 |
| A7 | -20, -3 | 1.0 |
| A8 | -10, -1 | 0.5011872336272722 |
| A9 | -12, 0 | 0.5011872336272722 |
| A10 | -25, -0.5 | 0.9440608762859234 |
| A11 | -18, 2 | 0.7079457843841379 |
| A12 | -10, 6 | 0.44668359215096315 |

### L/T. LevelMeter ve TrimDetector — 48 kHz; `sq(a, n)` = n örnek ±a dönüşümlü; `z(n)` = n sıfır

| ID | Girdi | Beklenen |
|---|---|---|
| L1 | sq(0.5, 48000) | mean -6.020599913279624, peak -6.020599913279624, count 48000 |
| L2 | sq(0.25, 48000) | mean -12.041199826559248, peak -12.041199826559248 |
| L3 | sq(0.5, 24000) + sq(0.25, 24000) | mean -8.061799739838872, peak -6.0206 |
| L4 | z(24000) + sq(0.5, 48000) | mean -6.0206, count 48000 |
| L5 | sq(0.5, 48000) + z(4800) | count 52800, mean -6.434526764861874 |
| L6 | sq(0.5, 24000) + z(14400) + sq(0.5, 24000) | count 48000, mean -6.0206 |
| L7 | sq(0.5, 24000) + z(4800) + sq(0.5, 24000) | count 52800, mean -6.434526764861874 |
| L8 | sq(0.5, 24000) + z(9600) + sq(0.5, 24000) | count 48000 |
| L9 | sq(0.5, 24000) + z(8640) + sq(0.5, 24000) | count 56640 |
| L10 | sq(0.003, 48000) | nil |
| L11 | sq(0.004, 48000) | mean ≈ -47.9588 (tolerans 1e-4) |
| L12 | z(48000) ve [] | nil |
| T1 | z(24000) + sq(0.5, 48000) + z(14400) | trimStart 0.5, trimEnd 0.3 |
| T2 | z(4800) + sq(0.5, 48000) + z(4800) | 0, 0 |
| T3 | z(48000) | nil |

### M. MixPlanBuilder — take id 1; c1 = (id 1, 1.0–2.0); r7 = (id 7, take 1, cue 1, "a.caf"); süre 10; hasAudio true

| ID | Değişiklik | Beklenen |
|---|---|---|
| M1 | TakeSettings.pythonParity | .hardMute; [(48000, 0, nil), (96000, 1, nil)]; klip start 48000, gain 1; limiter nil; bedGain 1 |
| M2 | varsayılan (duck) | E1 keyframe'leri; limiter nil |
| M3 | duckDepth 20 | limiter .standard; plato 0.2 |
| M4 | bgVolume 150 | bedGain 1.5, limiter .standard |
| M5 | bgVolume 200 | bedGain 1.5 |
| M6 | dubVolume 120 | klip gain 1.2, limiter |
| M7 | dubVolume 50, r7.volume 200 | gain 1.0, limiter nil |
| M8 | autoLevel, mean -30, peak -10 | gain ≈ 2.8183829 (Float), limiter |
| M9 | autoLevel, mean nil | gain 1.0 |
| M10 | autoLevel false, mean -30 | gain 1.0 |
| M11 | separated, stem ("bg.caf","sig"), derinlik 20 | .separated; zarf plato 0; limiter |
| M12 | separated, stem nil | .duck, uyarı [.separatedUnavailableUsedDuck]; derinlik 0 → limiter nil |
| M13 | separated, stem var, hasAudio false | .duck, uyarı; hasBedAudio false |
| M14 | kayıtlar [] | noRecordings, "En az bir replik kaydedilmeli" |
| M15 | yalnız take 2 kaydı | noRecordings |
| M16 | c1 start 90000 | invalidCueTime(90000), "Başlangıcı 90000.0 sn olan repliğin zaman bilgisi geçersiz, montaj yapılamadı. Lütfen bu repliği düzenleyip tekrar deneyin." |
| M17 | c1 start .nan | invalidCueTime (case kontrolü) |
| M18 | süre 0 ya da .nan | unknownDuration |
| M19 | sampleRate 0 | invalidSampleRate |
| M20 | c1 0.0–1.0, latency 0.02 | timelineStart 0, trimStart 960 |
| M21 | offset 0.1, latency 0.01, trimStart 0.2, trimEnd 0.3 | timelineStart 61920, trimStart 9600, trimEnd 14400 |
| M22 | c1 + c3 (3–4); kayıt sırası [c3, c1] | klipler c1, c3 |
| M23 | ek kayıt (id 9, cue 99 yok) | yok sayılır; orphanRecordingsIgnored(1) |
| M24 | ek c5 (5–6, kayıtsız), allCues | iki pencere; recordedCues ile yalnız c1 |
| M25 | pythonParity + allCues | yine yalnız c1 (D-14) |
| M26 | M2 canonicalString | aşağıdaki metin |
| M27 | M2 planHash | == PortableSHA256.hash(M2.canonicalString).hexString; M1 ve M3'ten farklı; iki kurulumda aynı |

M26:

```
mixplan/1
sr=48000
dur=480000
bedAudio=1
bed=3f800000
treat=duck;L=0;fo=3fe0000000000000;fi=3fe0000000000000;c=equal_power;sc=recorded;mr=0
k=24000;3f800000;equal_power
k=48000;0;-
k=96000;0;equal_power
k=120000;3f800000;-
c=7;1;a.caf;48000;0;0;3f800000
lim=none
```

M3 son satırı: `lim=3f59999a;3f747ae147ae147b;3fa999999999999a`.

### X. Protokoller

| ID | Beklenen |
|---|---|
| X1 | Mock EntitlementProvider (.normal), TranscriptionEngine (iki event yayıp biter), SeparationEngine derlenir |
| X2 | async XCTest: `await currentTier() == .normal` |
| X3 | Stream'den [.progress(0.5), .segment(...)] toplanır |

## 8. CI — `.github/workflows/ios-core.yml`

```yaml
name: ios-core
on:
  push:
    paths: ["ios/**", ".github/workflows/ios-core.yml"]
  pull_request:
    paths: ["ios/**", ".github/workflows/ios-core.yml"]
concurrency:
  group: ios-core-${{ github.ref }}
  cancel-in-progress: true
jobs:
  linux:
    runs-on: ubuntu-latest
    container: swift:6.0
    defaults:
      run:
        working-directory: ios/ChoosVoieCore
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift build --build-tests
      - name: swift test
        run: |
          set -o pipefail
          swift test 2>&1 | tee test.log
      - name: Report failures as annotation
        if: failure()
        run: |
          msg=$(grep -E "error:|failed|Fatal error|Crash" test.log | sed -E 's#^.*/Tests/##' | head -120 | cut -c1-400 | sed ':a;N;$!ba;s/%/%25/g;s/\r/%0D/g;s/\n/%0A/g')
          echo "::error title=linux test failures::${msg}"
  macos:
    runs-on: macos-latest
    defaults:
      run:
        working-directory: ios/ChoosVoieCore
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift test
```

## 9. Riskler

- R1: Windows'ta `String(format:)` tie yuvarlaması bilinmiyor; testlerde tie yok.
- R2: Windows'ta kullanıcı yolunda boşluk ve ASCII dışı karakter var (`C:\Users\Alperen Özkaya\…`); SwiftPM sorun çıkarırsa depoyu `C:\src\choicevoie` gibi bir yola klonla. `git config core.longpaths true`.
- R3: `JSONDecoder` yinelenen anahtar davranışı bilinmiyor.
- R4: Windows'ta `TimeZone(identifier:)` ICU'ya bağlı; testlerde yalnız `TimeZone(secondsFromGMT:)`.
- R5: CRLF — `.gitattributes` `eol=lf`; CRLF testleri açık `"\r\n"` kaçışıyla.

## 10. Kapsam dışı (Mac ya da sonraki faz)

AVFoundation tabanlı her şey (render, önizleme, AVAudioMix rampaları, ses içe aktarma, dalga formu, kayıt, gecikme ölçümü, voice processing); Speech/WhisperKit motorları; StoreKit EntitlementProvider uygulaması; EngineRegistry/ConsentGate/CloudClient; SwiftUI uygulaması; GRDB şeması/repository; JobCoordinator; limiter DSP, kenar fade'leri, high-pass, vDSP hızlandırmaları; StemAssembler; Q4b seçeneği.
