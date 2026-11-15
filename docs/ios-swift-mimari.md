# Choos Voie için Swift / iPhone mimarisi — ayrıntılı tasarım

Bu belge [ios.md](ios.md)'nin devamıdır: orada "iPhone'da çalışır mı, hangi araçlar hazır,
App Store ne diyor" sorusu cevaplanmıştı; burada "native Swift uygulaması nasıl
görünür, neyi hazır kullanırız, neyi eksik kalır, hangi hızlı API/model alternatifleri var"
sorusu ele alınır. Henüz bir iOS kodu yoktur; bu bir planlama belgesidir. Tarih: 2026-11-15.

Yön iki katmanlıdır: **Normal** (MVP; tamamen cihazda, backend ve işletme maliyeti yok) ve
**Pro** (sonra; abonelik, bulut ses ayırma, daha iyi bulut konuşma tanıma).

> **"Doğrulanmadı" / "Doğrulanamadı" / "Bilinmiyor" etiketi:** Ya kaynakta açıkça yazmayan
> ya da hiç ölçülmemiş bilgi demektir. Bu etiketli her madde geliştirmeye başlamadan önce
> Apple dokümanından veya Faz 0 ölçümüyle kontrol edilmelidir. `[A3]`, `[P8]`, `[V1]` gibi
> etiketler sayfa sonundaki [Kaynaklar](#kaynaklar) listesine bağlanır (2026-11-15'te
> kontrol edildi). Fiyatlar kaynak sayfalarından o tarihte alınmıştır ve değişebilir.

## Kısaca

- **Normal / Pro ayrımı:** Normal katman (MVP) kayıt, ses düzeltmeleri, montaj, auto-level,
  dalga formu ve konuşma tanımayı cihazda yapar; ağ, backend ve onay akışı gerekmez. Pro
  katman (Faz 3) abonelik + proxy backend ile bulut ayırma ve bulut STT ekler.
- **Konuşma tanıma:** MVP'de İngilizce, Apple `SpeechTranscriber` ile (cihazda, dosya
  girdili, zaman damgalı [V7, V8, V9]). Türkçe Faz 2'dir. `SpeechTranscriber`'ın İngilizce
  ve Türkçe desteği **Doğrulanamadı**; çalışma zamanında
  `SpeechTranscriber.supportedLocale(equivalentTo:)` ile kontrol edilir, yedek
  `DictationTranscriber` [V11]. Türkçe cihazda destekleniyorsa WhisperKit gerekmez, değilse
  WhisperKit.
- **Normal'de stem ayırma yok, fade'li ducking var:** cue içinde orijinal ses 100→0
  yumuşakça iner, cue bitince geri çıkar (bkz. [§5](#5-arka-plan-sesi-ducking-modu)). Gerçek
  arka plan ayırma Pro'ya ait. iOS'ta dosya tabanlı hazır ayırma API'si yok.
- **Pro ödemesi yalnız uygulama içi satın alma (IAP):** özellik kilidi için IAP zorunlu
  (Kural 3.1.1) [R1]; StoreKit 2 + `SubscriptionStoreView` [V12, V13].
- **Veri katmanı GRDB:** mevcut SQLite şeması taşınır (yeni sütunlarla); SwiftData'ya göre
  parite, açık migration ve test kolaylığı avantajlı.
- **LLM gerekmiyor (opsiyonel):** mevcut uygulamada hiçbir LLM/API çağrısı yok. İsteğe bağlı
  eklentiler için önce cihazdaki Foundation Models, bulut LLM yalnızca proxy + açık onayla
  (hızlı katman: `claude-haiku-5-5` vb.).
- **YouTube indirme yok** (App Store 5.2.3) — bkz. [ios.md §4](ios.md#4-youtube-ve-app-store-kuralları).

---

## iOS'ta yapılabilir mi? (Normal katman)

**Cevap: Evet.** Normal katmanın tüm kalemleri Apple framework'leri ve kendi saf Swift
kodumuzla yapılabilir. **Kısmi** olan üç nokta var: canlı önizlemede ducking eğrisinin
dışa aktarılanla birebir aynı olması, limiter'ı kendimizin yazması ve uzun render'ın arka
planda sürmesi. Bunlar dışa aktarılan dosyanın kalitesini etkilemez.

Risk sütunu: D = düşük, O = orta, Y = yüksek.

| # | Kalem | Sonuç | Framework / yaklaşım | Risk | Not |
|---|---|---|---|---|---|
| 1 | Güzel arayüz | Evet | SwiftUI, `@Observable`, `Canvas` (timeline) | O | uzun videoda timeline çizim performansı ölçülmeli |
| 2 | Video dosyadan içe aktarma | Evet | `PhotosPicker` (iOS 16.0+), `fileImporter` (iOS 14.0+), `AVURLAsset` | D | `.webm` Bilinmiyor (S0.5) |
| 3 | Elle cue + doğrulama | Evet | `CueValidator` (`app.py:517-546`) | D | |
| 4 | Otomatik cue (İngilizce) | Evet | `SpeechTranscriber` + `audioTimeRange` [A2, V8], `AssetInventory` [V10] | O | İngilizce desteği çalışma zamanında kontrol; cue bölme (duraklama tabanlı) bizim kod |
| 5 | Aralık transkripsiyonu 0,3–120 sn | Evet | aynı motor | D/O | |
| 6 | Toplu kaydırma | Evet | saf Swift | D | |
| 7 | JSON v1 / SRT | Evet | Foundation | D | birebir |
| 8 | Dalga formu | Evet | `AVAssetReader` + vDSP | D | yakınlaştırma için çok çözünürlüklü tepe (öneri: ek 100 tepe/sn seviye) |
| 9 | Cue başına kayıt | Evet | `AVAudioEngine` `installTap` | O | gecikme S0.3 |
| 10 | Cue başına ses dosyası içe aktarma | Evet | `fileImporter` + `UTType.audio` [V16] → `AVAssetReader`/`AVAudioConverter` → CAF LPCM | D/O | DRM Doğrulanmadı |
| 11 | Take'ler, ses seviyeleri | Evet | Swift + GRDB | D | |
| 12 | Auto-level | Evet | Accelerate | D | ±0,5 dB hedefi (S0.2) |
| 13 | Limiter | Kısmi | kendi look-ahead limiter'ımız; `AUPeakLimiter` Doğrulanmadı | O | `alimiter` ile birebir değil |
| 14 | Ducking (dışa aktarma) | Evet | kendi çevrimdışı mikserimiz, örnek başına kazanç | D | |
| 15 | Ducking (canlı önizleme) | Kısmi | `AVMutableAudioMixInputParameters.setVolumeRamp` [V1, V2, V3] | O | yedek: yalnız-ses önizleme render'ı |
| 16 | Render / yeniden render / bayat tespiti | Evet | `AVMutableComposition` + `AVAssetWriter`; MixPlan hash | D | |
| 17 | mp4 dışa aktarma / paylaşma / Fotoğraflar | Evet | `ShareLink`; Fotoğraflar'a yazma izni Doğrulanmadı | D | |
| 18 | Uzun render arka planda | Kısmi | arka plan API'leri Doğrulanmadı (S0.6) | O | idempotent iş, açılışta kurtarma |
| 19 | Stem ayırma | Hayır (bilinçli) | — | — | Pro katman |
| 20 | Türkçe STT | MVP'de hayır | — | — | Faz 2 (SpeechTranscriber Türkçe destekliyorsa o, değilse WhisperKit [G1]) |
| 21 | Backend yok, işletme maliyeti $0 | Evet | — | — | |

---

## 1. Mevcut uygulamanın envanteri

Tek süreçli FastAPI (`app.py`, 3056 satır), Jinja şablonları + vanilla JS, stdlib `sqlite3`,
bellek içi iş durumuna sahip daemon thread'ler. Kimlik doğrulama yok; arayüz metinleri
Türkçe. Kodun kullandığı DB dosyası `choosvoie.db` (`app.py:114`); repodaki
`choicevoice.db` eski şemalı, kullanılmayan bir dosyadır.

| # | Özellik | `app.py` | Ağırlık | iOS notu |
|---|---|---|---|---|
| 1 | Video yükleme (.mp4/.webm/.mov/.m4v) | 297-326 | hafif | `PhotosPicker` / `fileImporter`; `.webm` AVFoundation'da oynar mı: Bilinmiyor |
| 2 | YouTube indirme (≤480p, host beyaz listesi) | 424-486 | orta | App Store'da yasak (5.2.3) |
| 3 | Video listele/sil (cascade) | 287, 677-728 | hafif | DB cascade |
| 4 | Cue CRUD + doğrulama (≥0, bitiş>başlangıç, sonlu, ≤24 sa, bitiş ≤ süre) | 489-602 (`_clean_cue_fields` 517-546) | hafif | saf mantık |
| 5 | Toplu cue kaydırma (ya hep ya hiç) | 773-868 | hafif | saf mantık |
| 6 | Cue JSON v1 / SRT dışa-içe aktarma (1 MB / 500 cue; ekle/değiştir) | 892-1075 | hafif | Foundation |
| 7 | Tek aralık transkripsiyon (0,3–120 sn) | 1168-1272 | orta/ağır | MVP: `SpeechTranscriber` (İngilizce); Türkçe Faz 2 (dil desteği çalışma zamanında kontrol) |
| 8 | YouTube altyazısından otomatik cue (VTT) | 1294-1424 | hafif | 5.2.3 sorunu aynı |
| 9 | Whisper ile tüm videodan otomatik cue (`vad_filter`, ≤500 cue, ilerleme) | 1427-1515, 1598, 1632 | ağır | MVP: `SpeechTranscriber` segment/kelime zamanı + kendi cue bölücümüz (İngilizce); Türkçe Faz 2 |
| 10 | Dalga formu şeridi (1200 tepe, JSON önbellek) | 1959-2022 | hafif/orta | `AVAssetReader` + vDSP |
| 11 | Konuşma/arka plan ayırma (yalnız cue aralıkları, ±0,5 sn pad, <1 sn boşluk birleştirme, `.bg.m4a`, sha256 imza ile bayat tespiti, stereo "hafif" yedek) | 2129-2450 | ağır | Normal'de yok: yerine fade'li ducking ([§5](#5-arka-plan-sesi-ducking-modu)); gerçek ayırma Pro (bulut) |
| 12 | Dublaj kayıt arayüzü (3-2-1, preroll, canlı metre, cihaz seçimi, otomatik ilerleme) | 1652-1785, `dub.html` | hafif/orta | `AVAudioEngine` kaydı + cue başına dosyadan ses içe aktarma |
| 13 | Take + ses seviyeleri (`bg_volume` 0-150, `dub_volume` 0-200, kayıt başı 0-200, `auto_level`) | 2787-2940 | hafif | kazanç parametreleri + ducking parametreleri |
| 14 | Auto-level (hedef −20 dB RMS, +15 max artırma, −6 max kısma, −1 dB tepe tavanı, −45 dB sessizlik tabanı) | 1875-1956 | hafif | Accelerate |
| 15 | Montaj/render (cue pencerelerinde orijinal/bg susturma, `amix` + `alimiter` 0,85, AAC 192k, `-c:v copy` / `libx264` yedeği) | 2570-2784 | orta | sert susturma yerine ducking zarfı; bkz. [§10](#10-montajın-avfoundation-karşılığı) |
| 16 | Take listesi/detay/yeniden render (durum draft/rendering/done/error; bayat uyarısı) | 2943-3011 | hafif | durum makinesi |
| 17 | Açılışta yetim temizliği; ad hoc `ALTER TABLE` migration | 213-274 | hafif | GRDB `DatabaseMigrator` |

**Akış:** video ekle → cue'lar (elle / otomatik İngilizce / içe aktarma) → arka plan
tedavisi seçimi (sessiz / yumuşak geçiş (duck) / ayrılmış — yalnız Pro) → kayıt veya
dosyadan ses ekleme (taslak take'e) → kaydet ve render → take sayfasında ses ayarı + yeniden
render → mp4 / cue JSON-SRT dışa aktarma. TTS ve çeviri yoktur; "dublaj" kullanıcının kendi
sesidir.

**LLM/API tespiti (kesin): yok.** Koddaki tüm "LLM" benzeri eşleşmeler yerel Whisper
motoru ctranslate2'ye veya kullanılmayan bir `static/tts` temizliğine (`app.py:137-140`)
aittir. Tek ağ trafiği: yt-dlp ve model indirmeleri (HF whisper-small-mlx, faster-whisper,
demucs ağırlıkları).

**Modeller / performans (README, RTX 3060):** Whisper "small" (CUDA float16 / CPU int8 /
Apple Silicon'da mlx); Demucs `htdemucs`. Demucs 8 sn ses: 5 sn GPU / 36,6 sn CPU; 70 sn
videonun (43 sn cue) ayırması 12,1 sn GPU; Whisper small 70 sn video 2,7 sn GPU / ~60 sn
CPU. Apple Silicon veya iPhone ölçümü **yok**.

**Python'daki mevcut ses davranışı (parite referansı):** kaydı olan cue'ların birleşiminde
orijinal ses ani sıfırlanır, fade yoktur (`app.py:2684-2685`); `keep_background` açıksa
ayrılmış arka plan yalnız o pencerelerde çalar (2643-2647, 2688). Bed kazancı (`bg_volume`
0–150) orijinal ve bg için ortaktır (2673-2674). Yeni take varsayılanları: `keep_background` 0,
`bg_volume` 100, `dub_volume` 100, `auto_level` 0 (şema 231-253).

**Veritabanı şeması** (FK kısıtı yok):

- `videos(id, title, filename, created_at, bg_file, bg_method, bg_cue_sig, bg_error, source_url)`
- `cues(id, video_id, start_sec, end_sec, text)`
- `takes(id, video_id, name, created_at, status default 'draft', output_file, error, keep_background, bg_volume, rendered_at, rendered_rec_count, dub_volume, auto_level)`
- `recordings(id, take_id, cue_id, filename, created_at, volume, mean_db, peak_db, UNIQUE(take_id, cue_id))`

Dosyalar: `uploads/<uuid>.ext`, `uploads/rec/`, `uploads/bg/<video>.bg.m4a`,
`uploads/wave/<video>.json`, `outputs/<uuid>.mp4`, `bin/ffmpeg`.

Repoda test yok; Swift tarafındaki parite testleri Python çıktısından "altın" veriyle
kurulmalıdır.

---

## 2. iOS'ta hazır olanlar ve eksikler

Genel eşleme için bkz. [ios.md §2](ios.md#2-seçenekler). Aşağıda aşama aşama durum; ayrıntılı
araç açıklamaları için [ios.md §3](ios.md#31-konuşmayı-yazıya-çevirme--speechanalyzer-ios-26).

| Aşama | iOS'ta hazır | 3. taraf (cihazda) | Bulut | Eksik |
|---|---|---|---|---|
| Video / ses içe aktarma | `PhotosPicker` iOS 16.0+; `fileImporter` iOS 14.0+ (güvenlik kapsamlı URL'ler: `startAccessingSecurityScopedResource`); `UTType.audio` iOS 14.0+ [V16] — hepsi doğrulandı | — | — | YouTube indirme yasak, Kural 5.2.3 [R1]; `.webm` ve DRM'li ses: Doğrulanmadı |
| Zaman damgalı konuşma tanıma | `SpeechTranscriber`, `SpeechAnalyzer`, `AssetInventory`, `DictationTranscriber` iOS 26.0+ [A1, V6]. Dosya girdisi: `SpeechAnalyzer(inputAudioFile:modules:finishAfterFile:)` [V7]. Zaman damgası: `audioTimeRange` [A2]; `timeIndexedTranscriptionWithAlternatives` preset'i bunu açar [V8]; WWDC25: zaman kodları örnek düzeyinde hassas [V9]. Cihazda çalışan yeni model [V9]; modeller `AssetInventory` ile Apple sunucularından indirilir, uygulamalar arası paylaşılır, uygulama başına rezervasyon sınırı vardır [V10]. Yedek `DictationTranscriber` (eski cihazlarla uyumlu; cihazdaki `SFSpeechRecognizer` ile aynı diller) [V11]. **Dil desteği (İngilizce ve Türkçe): Doğrulanamadı** — [A3] yalnızca "cihaz desteklemiyorsa dizi boştur" der; `SpeechTranscriber.supportedLocale(equivalentTo:)` ile çalışma zamanında kontrol edilir. Cihaz listesi: Doğrulanamadı | **WhisperKit** (MIT, Core ML; tiny/base/small/large-v3/large-v3 turbo; kelime + segment zamanı) [G1]; Whisper (MIT) [G2]; whisper.cpp: Doğrulanmadı | Groq, OpenAI, Deepgram, AssemblyAI, ElevenLabs (Pro) | Apple tarafında konuşmacı ayrımı yok (WhisperKit SpeakerKit iOS16+, Pyannote v4 [G1]) |
| Konuşma/arka plan ayırma | Dosya API'si **yok**. `setVoiceProcessingEnabled` (iOS 13+) yalnızca mikrofon [A4]. Audio Mix yalnızca iPhone'un kendi uzamsal ses kayıtları için. **Normal katman ayırma yerine ducking kullanır** ([§5](#5-arka-plan-sesi-ducking-modu)) | Demucs (MIT) ama **2025-01-01'de arşivlendi**, fork: adefossez/demucs; `htdemucs` varsayılan, `htdemucs_ft` ~4× yavaş; CPU ≈ parça süresinin 1,5× [G3]. Core ML/ONNX port, boyut, iPhone hızı: Doğrulanmadı (Faz 4). Cihazda ayıran uygulamalar var ([ios.md kaynakları](ios.md#kaynaklar)) | Music.AI, ElevenLabs Voice Isolator, Replicate Demucs (Pro) | gerçek ayırma yalnız Pro / Faz 4 |
| Kayıt | `AVAudioEngine`; voice processing iOS 13+ [A4] = yankı engelleme + otomatik kazanç düzeltme (AGC) [V14]; `isVoiceProcessingAGCEnabled` varsayılan açık [V15]. Gürültü bastırma belgede adlandırılmıyor: Doğrulanamadı | — | — | gecikmeyi ölç ve telafi et |
| Montaj/render | `AVAudioEngine` çevrimdışı manuel render iOS 11+ [A5]; `AVMutableComposition` / `AVAssetExportSession` / `AVAssetWriter` ([ios.md §3.3](ios.md#33-montaj--avfoundation)). `AVMutableAudioMixInputParameters` `setVolumeRamp` ve `setVolume(_:at:)` iOS 4.0+, değer 0,0–1,0 [V1, V2]; `AVPlayerItem.audioMix` oynatmada uygulanır (yalnız dosya tabanlı medya, HLS değil) [V3]; `AVAssetExportSession.audioMix` dışa aktarmada [V4]; `AVAssetReaderAudioMixOutput` `audioMix` kabul eder [V5] | — | — | üst üste binen rampa, Passthrough preset'inde `audioMix`, rampa doğrusallığı/örnek hassasiyeti: Doğrulanamadı (S0.8) |
| Arayüz | `VideoPlayer` (SwiftUI) iOS 14.0+, `AVPlayerViewController` iOS 8.0+ (PiP) — doğrulandı. Standart SwiftUI bileşenleri Liquid Glass kullanır; özel görünümlerde `glassEffect(_:in:)` iOS 26.0+ [V17] | — | — | hazır timeline/cue editörü bileşeni yok (hiçbirinin olmadığı Doğrulanamadı) → özel `Canvas` |
| Abonelik / ödeme (Pro) | StoreKit 2: `Product`, `Transaction`, `Transaction.currentEntitlements`, `Transaction.updates` iOS 15.0+; `updates` dinleyicisi uygulama açılışında bir `Task`'ta başlatılmazsa bekleyen işlemler kaçabilir [V12]. `SubscriptionStoreView` iOS 17.0+: hazır abonelik ekranı [V13] | — | — | sunucuda abonelik doğrulama (App Store Server API / imzalı işlem): Doğrulanmadı |
| Depolama | SwiftData / Core Data / iCloud (Doğrulanmadı) | GRDB (mevcut SQLite şemasına en yakın; Doğrulanmadı) | — | karar gerekir, [§9](#9-veri-modeli-ve-depolama) |
| Cihazda LLM | Foundation Models iOS 26.0+: özetleme, varlık çıkarma, düzeltme, `@Generable` yapılandırılmış çıktı, araç çağırma; Apple Intelligence'lı cihaz gerekir [A6]; diller = Apple Intelligence dilleri [A7]; **Türkçe destekli** (destek sayfası 2026-11-05 tarihli) [A8]; bağlam penceresi belgelenmemiş; çeviri iddiası yok | — | Private Cloud Compute veya herhangi bir sunucu sağlayıcı [A6] | bağlam penceresi belirsiz |
| Çeviri | Translation framework iOS 17.4+ (`TranslationSession`, `LanguageAvailability`) [A9]; Türkçe/cihazda: Doğrulanmadı | — | LLM API'leri | çalışma zamanında kontrol |
| TTS | `AVSpeechSynthesizer`; Personal Voice yetkisi iOS 17.0+ [A10]; Türkçe Personal Voice: Doğrulanmadı | WhisperKit TTSKit (Qwen3-TTS, iOS 18+), **Türkçe yok** [G1] | ElevenLabs, Deepgram Aura, OpenAI TTS | doğal Türkçe TTS muhtemelen bulut ister (uygulama bugün TTS kullanmıyor) |

**iOS'ta eksik olanlar:**

1. Dosya tabanlı konuşma/arka plan ayırma API'si yok → Normal'de ducking, Pro'da bulut ayırma.
2. `SpeechTranscriber` İngilizce ve Türkçe desteği Doğrulanamadı → çalışma zamanında
   kontrol; Türkçe Faz 2 (destek varsa Apple, yoksa WhisperKit).
3. Apple konuşma tanımada konuşmacı ayrımı yok.
4. Türkçe Personal Voice / TTSKit Doğrulanmadı.
5. YouTube medya indirme yasak.
6. Foundation Models bağlam penceresi belgesiz; Apple Intelligence olmayan cihazlarda yok.
7. Dosyada gürültü azaltma için belgelenmiş Apple API'si bulunamadı (yokluğu kanıtlanmadı).
   `AVAudioUnitEQ` yalnız çok bantlı EQ + `globalGain` sunar.

> [ios.md §3.1](ios.md#31-konuşmayı-yazıya-çevirme--speechanalyzer-ios-26) için güncelleme:
> `audioTimeRange` zaman damgası doğrulandı [A2, V8] ve dosya girdisi doğrulandı [V7];
> "Türkçe desteği kontrol edilmeli" maddesi geçerli kalır (Doğrulanamadı, çalışma
> zamanında `supportedLocale(equivalentTo:)`).

---

## 3. Benzer uygulamalar ve kullandıkları teknoloji

| Uygulama | Ne yapar | Teknoloji | Kaynak |
|---|---|---|---|
| ElevenLabs Dubbing | Yapay zekâ dublaj | Bulut API (v1 $0,33/dk filigranlı, $0,50 filigransız; v2 $2,20) | [P6] |
| Moises / Music.AI | Stem ayırma | Music.AI bulut modülleri [P8]; Moises ilişkisi ve cihazda çalışan kısım: Doğrulanmadı | [P8] |
| SongSplit AI, VSep, Stem Splitter | Stem ayırma | Cihazda ([ios.md kaynakları](ios.md#kaynaklar)) | ios.md |
| Lalal.ai | Stem, Voice Cleaner | Bulut API; fiyat Doğrulanmadı | [P9] |
| AudioShake | Stem | REST API ve SDK; iOS/cihazda çalışma belirtilmemiş | [P10] |
| HeyGen, Rask, CapCut, Smule, Speechify, shadowing uygulamaları | — | Doğrulanmadı, kaynaklanmadı | — |

Çıkarım: ayırma tarafında hem cihazda çalışan uygulamalar hem bulut API'ler var; dublajı
yapay zekâyla üretenler (ElevenLabs) bulut kullanıyor. Choos Voie'nin ayrıştırıcı yönü
"kullanıcı kendi sesini kaydeder" olduğu için TTS/dublaj API'sine ihtiyaç duymaz.

---

## 4. Mimari: Normal ve Pro katmanları

Kullanıcı yönü: önce **Normal** (tamamen cihaz, backend yok, işletme maliyeti yok), sonra
**Pro** (abonelik + bulut). Önceki hibrit çerçeve (bulutu v1'e koymak) bu yönle
değiştirildi; bulut yalnız Pro'ya kilitlidir.

| | Normal (MVP) | Pro (Faz 3) |
|---|---|---|
| Çalışma | tamamen cihaz | cihaz + proxy backend |
| STT | `apple.speechtranscriber` (İngilizce); Faz 2: Türkçe (Apple destekliyorsa o, değilse `whisperkit`) | + `cloud.groq` / `cloud.deepgram` ([§11](#11-pro-katmanı-api-alternatifleri-ve-abonelik) fiyatları) |
| Arka plan | `hardMute`, `duck` | + `separated` (stem): Music.AI [P8], yedek Replicate [P12] |
| Ses temizleme | yerel düzeltmeler ([§6](#6-ses-düzeltmeleri)) | öneri: ElevenLabs Voice Isolator $0,12/dk [P6] kullanıcının kendi sesine |
| Ödeme | yok | StoreKit 2 otomatik yenilenen abonelik; IAP zorunlu (3.1.1) [R1] |
| Backend | yok | proxy: auth, aboneliğin sunucuda doğrulanması (App Store Server API / imzalı işlem: Doğrulanmadı), kullanıcı başı günlük dakika tavanı, kill switch |
| Kullanıcı onayı | gerekmez (ağ yok) | 5.1.2(i): üçüncü taraf yapay zekâ dahil paylaşım için açık izin [R1] |
| 10 dk video maliyeti | $0 | ayırma kullanılırsa ≈$0,30–0,50 (yalnızca cue aralıkları; README örneğinde %61 cue → tahmin); STT ≈$0,007 |
| Abonelik düşerse | — | Pro motorları gizlenir; `separated` take'ler stem önbelleği varsa render edilir, yoksa `duck`'a düşer + uyarı (öneri) |

`SeparationMethod` değerlerinden `light` ve `companion` Normal'de kullanılmaz; `companion`
yalnız geliştirici bayrağıdır. Modül ve protokol ayrımı için bkz. [§8](#8-önerilen-uygulama-mimarisi)
ve [§14](#14-çekirdek-protokoller).

**Öneri:** MVP'yi Normal olarak çıkar; Pro'yu ayrı fazda (Faz 3) ekle. Gerekçe: Normal'de
ağ/backend/onay/maliyet yok (5.1.2(i) devreye girmez); mute modu `duck(seviye 0, fo 0, fi 0)`
ile tek kod yolundan çalışır; Pro yalnız yeni motorlar ve `BackgroundTreatment` durumu ekler.

### Karşılaştırılan önceki seçenekler

| Ölçüt | (a) Tam cihazda | (b) Hibrit (bulut v1'de) | (c) Bulut ağırlıklı |
|---|---|---|---|
| Ayırma | Kendi Core ML Demucs'umuz (hız/boyut/bellek Doğrulanmadı) | Light (stereo) + Cloud/Companion | Music.AI $0,05/dk [P8] / Replicate ~$0,017/çalıştırma [P12] |
| STT | WhisperKit [G1] / Apple | Apple/WhisperKit; isteğe bağlı Groq | Groq turbo $0,04/saat [P5b] |
| Backend | Yok | v1'de ince proxy | Zorunlu: proxy + auth + maliyet tavanı |
| Sonuç | Core ML Demucs'a bağımlı (upstream arşivlendi [G3]) → Faz 4 | Reddedildi: kullanıcı Normal'i backend'siz istiyor | Pro'nun bulut kısmı olarak kaldı |

Diğer elenenler: yalnız sert susturma (ani geçiş, tık olabilir; `mute` modu olarak kalıyor);
Light stereo (orta kanal iptali; yalnız stereo, kalite bilinmiyor; ducking yetmezse ayrı
spike); MVP'de Core ML Demucs (Doğrulanmadı); cue başına zarf minimumu (birleştirmesiz;
V şeklinde kısmi toparlanma = pompalanma); önizlemede `AVAudioEngine` ile gerçek zamanlı özel
mikser (birebir ama daha çok iş; ikinci yedek); WhisperKit'i MVP'de birincil yapmak
(İngilizce için Apple yeterli ve ek indirme gerektirmiyor; Türkçe Faz 2).
[ios.md Seçenek A](ios.md#2-seçenekler) (Safari + sunucu) kişisel kullanım için hâlâ en
hızlı yoldur.

### Companion backend (geliştirici bayrağı)

Normal katmanda kullanıcıya sunulmaz; yalnız geliştirici bayrağıyla deneysel
`SeparationEngine` uygulamasıdır.

| | Companion (LAN'da Mac/PC) | Companion (küçük bulut sunucu) | 3. taraf (Music.AI, Pro) |
|---|---|---|---|
| Kod | Demucs/Whisper korunur; ancak `separate_audio` `video_id`/DB'ye bağlı (`app.py:2256-2305`) → durumsuz `POST /separate` (segment wav girer, `no_vocals` çıkar) yazılmalı | Aynı | Yalnızca HTTP istemcisi |
| Güvenlik | Bugün auth yok; token + HTTPS eklenmeli; iOS Local Network izni (Info.plist anahtarı Doğrulanmadı) | token, TLS, kötüye kullanım önlemi | API anahtarı uygulamada tutulamaz → proxy |
| Maliyet | $0 (bilgisayar açık olmalı) | GPU sunucu fiyatı Bilinmiyor | kullandıkça öde |
| Kalite | `htdemucs` bilinen | aynı | Music.AI doğrudan arka plan stem'i verir [P8]; ElevenLabs Voice Isolator yalnız ses verir [P6] → ayırma için uygun değil |

### Kararı ne değiştirir

| Koşul | Sonuç |
|---|---|
| S0.7 ducking dinleme testinde ≥4/5 klipte duck > mute tercih edilmezse | sıradaki adım: Light stereo spike'ı (bkz. [§5](#5-arka-plan-sesi-ducking-modu) yedek sırası) |
| Q1 = yalnızca kişisel kullanım | Pro (IAP, proxy, bulut) iptal; Normal + Companion bayrağı |
| Q2 = işletilebilir backend yok | Pro ertelenir; Normal etkilenmez |
| Cihazda `SpeechTranscriber.supportedLocale(equivalentTo:)` Türkçe için destek döner ve zaman doğruluğu yeterli (S0.1-tr) | Türkçe için WhisperKit gerekmez |
| Core ML Demucs iPhone 17'de ≥1× gerçek zaman + boyut/bellek kabul edilebilir (Faz 4 spike'ı) | ayırma cihaza taşınabilir; bulut ayırma yedek kalır |

---

## 5. Arka plan sesi: ducking modu

Normal katmanda stem ayırma yoktur. Bunun yerine, cue içinde orijinal ses **yumuşak bir
fade ile kısılır** ve cue bitince geri açılır (ducking). Python'daki sert susturma
(`app.py:2684-2685`) ani olduğu için tık yapabilir; ducking aynı davranışın yumuşatılmış
hâlidir.

### Parametreler

Her take için saklanır (`takes` sütunları, bkz. [§9](#9-veri-modeli-ve-depolama)).

| Parametre | Sütun | Tip / aralık | Varsayılan | Anlam |
|---|---|---|---|---|
| Mod | `duck_mode` | TEXT `mute`/`duck`/`separated` | `duck` (yeni take) | `mute` = Python paritesi; `separated` yalnız Pro |
| Derinlik | `duck_depth` | INT 0–100 | 0 | cue içinde orijinalden kalan % |
| Fade-out | `fade_out_sec` | REAL 0–3,0 | 0,5 | rampa cue başında biter: [s−fo, s] |
| Fade-in | `fade_in_sec` | REAL 0–3,0 | 0,5 | rampa cue bitişinde başlar: [e, e+fi] |
| Eğri | `duck_curve` | TEXT `equal_power`/`linear`/`s_curve` | `equal_power` | |
| Kapsam | `duck_scope` | TEXT `recorded`/`all` | `recorded` | kaydı olan cue'lar / tüm cue'lar |

Üst sınır 3,0 sn bir öneridir. `mute` = `duck(fo=0, fi=0, derinlik=0)`; tek kod yolu.

**Kullanıcı örneği, birebir:** cue 1–2 sn, fo = 0,5, fi = 0,5, derinlik 0.

| Zaman | Orijinal ses kazancı | 48 kHz örnek |
|---|---|---|
| 0,0 – 0,5 sn | 1 (tam ses) | — |
| 0,5 → 1,0 sn | fade-out: 1 → 0 (`equal_power`: orta noktada 0,707 ≈ −3 dB) | 24000 → 48000 |
| 1,0 – 2,0 sn (cue) | 0 (derinlik 0) | 48000 – 96000 |
| 2,0 → 2,5 sn | fade-in: 0 → 1 | 96000 → 120000 |
| 2,5 sn sonrası | 1 | — |

Aynı videoda 2,8–3,5 sn'de ikinci bir cue olsaydı: aradaki boşluk 2,8 − 2,0 = 0,8 sn <
fo + fi = 1,0 sn olduğundan iki cue birleşir ve ses 1,0–3,5 sn boyunca kısık kalır
(pompalanma yok).

### Eğriler

u ∈ [0,1], L = derinlik/100. Fade-out için g(u) = L + (1−L)·c(u); fade-in bunun aynasıdır.

| Eğri | c(u) | Orta nokta (L=0) | Değerlendirme |
|---|---|---|---|
| `linear` | 1−u | 0,5 (−6 dB) | algı logaritmik, sonda "çöküş" hissi; test/parite için |
| `equal_power` (önerilen) | cos(π/2·u) | 0,707 (−3 dB) | ilişkisiz sinyaller (orijinal ve kullanıcı sesi) arasında toplam güç hissi sabit kalır |
| `s_curve` | (1+cos(π·u))/2 | 0,5 | iki ucu yumuşak; alternatif |
| dB-doğrusal | 0 dB → 20·log10(L) | — | L=0'da −∞; yalnız L>0 |

Pro `separated` modunda orijinal ↔ stem geçişi doğrusal çapraz geçiştir (ilişkili
sinyaller, genlik toplamı sabit).

### Zarf algoritması

`DuckEnvelopeBuilder` (saf Swift):

```
W = kapsamdaki cue'lar (recorded: kaydı olanlar | all: hepsi), start'a göre sıralı
birleştir: sıradaki.s − son.e < fo + fi  →  son.e = max(son.e, sıradaki.e)   // arada ducklı kal
         (üst üste binen cue'lar da birleşir; fo=fi=0'da Python'un between() birleşimine iner)
her birleşik [s,e] için:
  a = max(0, s − fo)          // video başında fade kısaltılır; s == 0 ise L'den başlar
  b = min(D, e + fi)          // video sonunda kısaltılır; e ≥ D ise sona kadar L
  keyframe'ler: (a,1) →eğri→ (s,L) —sabit— (e,L) →eğri→ (b,1)
örnek = round(t · 48000)
```

Bu birleştirme sayesinde `AVAudioMix`'e hiç üst üste binen rampa gitmez (belgelenmemiş
davranışa bağımlılık yok).

### Kurallar

| Kural | Karar | Gerekçe |
|---|---|---|
| Boşluk < fo + fi | ducklı kal | pompalanma olmasın |
| Neredeyse çakışma | `minRecoverSec` (varsayılan 0) önerisi; dinleme testiyle karar | 50 ms'lik çıkış da pompalanma yapar |
| Video başı/sonu | rampayı kısalt | belirleyici davranış |
| Kayıt cue'dan uzun (Q4b) | varsayılan: duck bitişi = cue bitişi; seçenek: max(cue.e, klip sonu) | Q4b |
| Kapsam | varsayılan `recorded` | kaydı olmayan cue'da orijinal tek içeriktir; `all` alıştırma seçeneği |

### Karşılaştırma

| | Sert susturma (Python) | Duck derinlik 0 | Duck kısmi %15–25 | Ayrılmış stem (Pro) |
|---|---|---|---|---|
| Geçiş | ani (~20 ms çerçeve, Doğrulanmadı), tık olabilir | yumuşak | yumuşak | yumuşak (çapraz) |
| Ambiyans/müzik cue içinde | kaybolur | kaybolur | kısmen kalır | korunur |
| Orijinal konuşma cue içinde | yok | yok | sızar: %15 ≈ −16,5 dB, %20 ≈ −14 dB, %25 ≈ −12 dB | yok (artefakt olabilir) |
| Maliyet / ağ | $0 / yok | $0 / yok | $0 / yok | Music.AI $0,05/dk [P8] / ağ |
| Karmaşıklık | çok düşük | düşük | düşük | yüksek |

Kısmi derinlik önerisi: müzik/ambiyans yoğun sahnede %15–25, konuşma yoğun sahnede 0.
Dezavantajı "çift ses"tir; varsayılan 0, S0.7 karar verir.

**Ducking yetmezse sıra:** kısmi derinlik → Light stereo (orta kanal iptali, yalnız stereo,
ayrı spike) → Core ML Demucs (Faz 4) → Pro bulut ayırma.

### Mikser ve önizleme eşlemesi

| Hedef | Uygulama | Belirsizlik |
|---|---|---|
| (a) Çevrimdışı mikser (dışa aktarma) | 1 sn blok başına keyframe'lerden kazanç dizisi: sabit bölge `vDSP_vfill`, rampa 1024 noktalı eğri tablosu; bed × `bedGain` × zarf (`vDSP_vmul`); `separated`'da stem × (1 − zarf_doğrusal) | yok; birim testle örnek doğruluğu |
| (b) Canlı önizleme | bed track `AVMutableAudioMixInputParameters`: sabit bölge `setVolume(_:at:)`, her rampa N=8 doğrusal alt rampa (`setVolumeRamp`); değer min(1, `bedGain`·g) | 0–1 sınırı doğrulandı [V1, V2]; `AVPlayerItem.audioMix` oynatmada uygulanır [V3]; rampa doğrusallığı, rampa sayısı sınırı, seek sonrası doğruluk Doğrulanamadı |
| (b) Yedek | yalnız-ses önizleme render'ı: mikser `tmp/preview.caf` → `AVMutableComposition` ile video | süre ölçülmedi (S0.6) |

Dışa aktarma için `AVAssetExportSession.audioMix` [V4] ve özel mikser için
`AVAssetReaderAudioMixOutput` [V5] da vardır. `AVAudioMix` her yerde (dışa aktarma dahil)
yalnız şu koşullarda yeterli olur: >1 dublaj kazancından ve limiter'dan vazgeçilirse ve
S0.8, export preset'inin `audioMix`'i uyguladığını gösterirse. Bu yüzden varsayılan:
önizleme `AVAudioMix` rampalarıyla, dışa aktarma kendi vDSP mikserimiz + limiter ile.

**Limiter koşulu** genişler: `max_gain>1` || (`mode==duck` && `depth>0`) || `mode==separated`
(S0.2 ölçer).

---

## 6. Ses düzeltmeleri

Normal katmanda, tamamen cihazda.

| # | Düzeltme | Ne zaman | Yaklaşım | Varsayılan | Durum |
|---|---|---|---|---|---|
| 1 | Voice processing | kayıt | `setVoiceProcessingEnabled` [A4]: yankı engelleme + AGC [V14]; AGC varsayılan açık [V15] | **KAPALI** (AGC, auto-level ile çakışır); hoparlörle/kulaklıksız kayıt için AGC kapalı seçenekli anahtar | MVP; karar S0.3 dinleme testinde |
| 2 | Gecikme telafisi | kayıt sonrası | `latency_comp_sec` = `inputLatency` + `outputLatency` + `ioBufferDuration`; kullanıcı ofseti ±200 ms | ölçülen | MVP; ≤20 ms |
| 3 | Sessizlik kırpma (baş/son) | kayıt/içe aktarma sonrası, yıkıcı değil | −50 dBFS altı ≥0,2 sn; `trim_start_sec`, `trim_end_sec` | açık | MVP; konum korunur: klip `start_sec + trim_start`'ta başlar; opsiyonel "cue başına hizala" |
| 4 | Kenar fade'leri | mikser | klip başı/sonu 5 ms | açık | MVP; tık önleme |
| 5 | Auto-level | render | `AutoLevel` sabitleri; ölçüm kırpılmış bölgede | Python paritesi: kapalı; öneri: yeni take'te açık | MVP |
| 6 | Limiter | render | look-ahead 0,85, 5/50 ms | koşullu ([§5](#5-arka-plan-sesi-ducking-modu)) | MVP |
| 7 | İçe aktarılan dosya dönüşümü | içe aktarma | 48 kHz mono CAF/LPCM; stereo→mono ortalama; `source='import'`, `latency_comp=0`, kaydırma ayarı | — | MVP; DRM Doğrulanmadı → net hata mesajı |
| 8 | High-pass / DC kesme ~80 Hz | render | `vDSP_biquad` veya `AVAudioUnitEQ` (Doğrulanmadı) | kapalı | sonra |
| 9 | Dosyada gürültü azaltma | — | belgelenmiş Apple dosya API'si bulunamadı | — | sonra / Pro (Voice Isolator) |
| 10 | EQ preset, kompresör, de-esser | — | Doğrulanmadı | — | sonra |

Voice processing'in gürültü bastırma yaptığı belgede adlandırılmıyor (Doğrulanamadı).
`AVAudioSession` `.measurement` modu sistem sinyal işlemesini en aza indirir (doğrulandı).

İçe aktarılan ses süresi için öneri: ≤ cue süresi + 10 sn, aksi halde uyarı (Q4b).
`recordings` ek sütunları için bkz. [§9](#9-veri-modeli-ve-depolama).

---

## 7. Arayüz taslağı

| Ekran | Bileşenler | Etkileşimler |
|---|---|---|
| Kütüphane | `NavigationStack`, liste/ızgara, küçük resim (`AVAssetImageGenerator`: Doğrulanmadı), `PhotosPicker`, `fileImporter` | içe aktar, kaydırarak sil, take sayısı/durum rozeti |
| Video detayı / Cue editörü | üstte `VideoPlayer`/`AVPlayerLayer`; altta `Canvas` timeline: dalga formu, cue blokları, duck zarfı katmanı (yarı saydam rampalar); oynatma kafası `addPeriodicTimeObserver` | sürükle-taşı, kenar tutamakları (`DragGesture`, 10 ms yakalama), `MagnifyGesture` yakınlaştırma, uzun basış menüsü (böl/sil/transkribe), toplu kaydırma, "Otomatik cue (English)" + ilerleme, JSON/SRT |
| Kayıt | büyük cue metni, 3-2-1, preroll (önizlemede ducking), canlı metre, giriş cihazı | kaydet/tekrar/dinle/sonraki; "Dosyadan ekle"; kırpma önizlemesi |
| Take mikseri | orijinal 0–150, dublaj 0–200, kayıt başı 0–200, auto-level; arka plan segment kontrolü (Sessiz / Yumuşak geçiş / Ayrılmış [Pro kilidi]); derinlik, fade-out, fade-in; kapsam; eğri (gelişmiş) | önizle, bayat rozeti, render |
| Dışa aktarma | ilerleme, `ShareLink`, Fotoğraflar'a kaydet, JSON/SRT | iptal, yeniden render |

Liquid Glass: standart SwiftUI bileşenleri otomatik kullanır; özel görünümlerde
`glassEffect(_:in:)` ve `GlassEffectContainer` (iOS 26.0+) [V17]. Hazır timeline/cue editörü
bileşeni bulunamadı; timeline özel çizilir (Doğrulanamadı: hiçbirinin olmadığı).

---

## 8. Önerilen uygulama mimarisi

Xcode projesi + yerel Swift Package'lar.

| Katman | Modül | Sorumluluk |
|---|---|---|
| App | `ChoosVoieApp` | kompozisyon kökü, DI, feature flag, yaşam döngüsü (yarım iş temizliği) |
| Feature | `LibraryFeature` | liste, `PhotosPicker`/`fileImporter`, silme |
| Feature | `CueEditorFeature` | CRUD, toplu kaydırma, dalga formu, aralık transkripsiyonu, otomatik cue, JSON/SRT |
| Feature | `RecorderFeature` | 3-2-1, preroll, canlı metre, cihaz seçimi, otomatik ilerleme, dinleme, dosyadan ses içe aktarma |
| Feature | `TakesFeature` | ses seviyeleri, ducking ayarları, auto-level, render/yeniden render, bayat uyarısı, paylaş/Fotoğraflar |
| Feature | `SeparationFeature` (Pro) | başlat, ilerleme, bayat, motor seçimi + onay |
| Core (saf Swift) | `Domain` | modeller, `CueValidator` (`app.py:517-546`), `BulkShift`, `SegmentMerger` (2129), `CueSignature`, `MixPlanBuilder`, `AutoLevel`, `DuckEnvelopeBuilder`, `TrimDetector` |
| Core (saf Swift) | `CueIO` | JSON v1/SRT, 1 MB/500 sınırı, ekle/değiştir |
| Core (platform) | `Transcription` | `TranscriptionEngine`: SpeechTranscriber / WhisperKit / Cloud |
| Core (platform) | `Separation` (Pro) | `SeparationEngine`: Cloud / CoreML (+ Companion geliştirici bayrağı) + `StemAssembler` (adelay+apad karşılığı, %2 süre kontrolü, atomik değiştirme) |
| Core (platform) | `AudioAnalysis` | 1200 tepe (`AVAssetReader` + vDSP), mean/peak dB |
| Core (platform) | `AudioImport` | `fileImporter` URL'si → CAF LPCM dönüşümü, DRM/biçim hata mesajları |
| Core (platform) | `Rendering` | `MixRenderer` (export), `PreviewComposer` (`AVPlayer`), `Limiter` |
| Core (platform) | `Recording` | `AVAudioEngine`, gecikme telafisi, voice processing anahtarı |
| Core (platform) | `Persistence` | GRDB şeması, migrator, repository, dosya deposu |
| Core (platform) | `Jobs` | `JobCoordinator` actor, ilerleme, termal/iptal |
| Core (platform) | `Entitlements` | StoreKit 2: `EntitlementProvider`, `Transaction.updates` dinleyicisi, `EngineRegistry` |
| Core (platform) | `CloudClient` (Pro) | proxy, onay kapısı, maliyet tavanı, kill switch |

### Eşzamanlılık (Swift 6 strict)

| Konu | Karar |
|---|---|
| UI / ViewModel | `@MainActor` + `@Observable` |
| Ağır işler | `JobCoordinator` actor; STT, ayırma (Pro), render tek seri kuyrukta (termal/bellek) |
| İlerleme | `AsyncThrowingStream<JobEvent>`; ETA hesabı Python mantığıyla |
| İptal | cooperative; segment/blok sınırında `Task.checkCancellation()` |
| DB | GRDB `DatabasePool` (WAL), `ValueObservation` → UI |
| Kayıt | `AVAudioEngine` `installTap` → dosya + metre; gerçek zamanlı thread'de actor/lock/alloc yok; metre `AsyncStream` (tap thread'i Doğrulanmadı) |
| Kurtarma | iş durumu DB'de; açılışta `rendering`/`separating` → `error("Yarıda kesildi")` (`app.py:213-274` karşılığı) |
| Arka plan | `BGProcessingTask` / `BGContinuedProcessingTask` / `beginBackgroundTask` **Doğrulanmadı**; varsayım: işler yalnız ön planda garanti, idempotent + devam ettirilebilir (segment önbelleği, atomik çıktı) — S0.6 |
| Bulut (Pro) | `URLSession` background config (askıda devam Doğrulanmadı) |
| Abonelik (Pro) | `Transaction.updates` dinleyicisi uygulama açılışında bir `Task`'ta başlar [V12] |
| Termal | `ProcessInfo.thermalState` ≥ `.serious` → yeni ağır iş başlamaz, mevcut iş segment sınırında durur (eşik varsayım) |

### Veri akışı

```
İçe aktar → [Media/videos] + videos satırı → (WaveformJob → Caches)
CueEditor ⇄ cues (doğrulama Domain'de) ⇄ CueIO (JSON v1/SRT)
  └─ TranscriptionEngine (SpeechTranscriber, en) → [TranscriptSegment] → cue taslakları (≤500)
Recorder → rec/*.caf (+ latency_comp, mean_db, peak_db kayıt anında) → recordings (UNIQUE take+cue)
  └─ dosyadan içe aktarma (AudioImport) → rec/*.caf (source='import')
Takes: MixPlanBuilder(take, recs, cues, video, treatment) → DuckEnvelopeBuilder → MixPlan (hash)
         → MixRenderer → outputs/*.mp4 (atomik)
         └→ PreviewComposer (AVPlayer + AVAudioMix rampaları, render'sız dinleme)
Pro: SeparationJob: cues → SegmentMerger → SeparationEngine (segment) → StemAssembler → bg.m4a + imza
```

---

## 9. Veri modeli ve depolama

### GRDB mi, SwiftData mı?

| Ölçüt | GRDB (seçilen) | SwiftData |
|---|---|---|
| Şema birebir | aynı SQL, isimler korunur | model sınıflarına çeviri |
| UNIQUE / FK / CASCADE | doğrudan SQL | `#Unique` / `deleteRule` (Doğrulanmadı) |
| Sürümlü migration | `DatabaseMigrator` | var; karmaşık ayrıntı Doğrulanmadı |
| Test / parite | bellek içi DB | daha zor |
| `choosvoie.db` açabilme | mümkün | hayır |
| iCloud senkron | kendin yaz | CloudKit (Doğrulanmadı) |
| Bağımlılık | 3. taraf (sürüm/lisans Doğrulanmadı) | yok |

Gerekçe: parite, açık migration ve test edilebilirlik, iCloud senkronundan ağır basıyor.
iCloud gereksinim olursa karar yeniden açılır. Bağımlılık riski için repository arayüzü
değiştirilebilir tutulur.

### Şema eşlemesi

| Tablo | Python'a göre fark |
|---|---|
| `videos` | aynı + `duration_sec`, `has_audio`, `is_stereo` (içe aktarmada bir kez); `source_url` yalnızca bilgi; `bg_method` değerleri `light`/`companion`/`cloud`/`coreml` (Normal'de kullanılmaz; Pro/geliştirici); + `bg_sig_version` |
| `cues` | aynı + FK CASCADE + `INDEX(video_id, start_sec)` |
| `takes` | aynı + `rendered_plan_hash` (bayat = güncel MixPlan hash'i ≠ render hash'i; `rendered_rec_count` geriye uyum için kalır) + ducking sütunları (aşağıda) |
| `recordings` | aynı + `duration_sec`, `latency_comp_sec`, `sample_rate`, `source`, `trim_start_sec`, `trim_end_sec`, `offset_sec`; `mean_db`/`peak_db` kayıt anında hesaplanır |

**`takes` ducking sütunları:** `duck_mode` TEXT (`duck` varsayılan), `duck_depth` INT 0,
`fade_out_sec` REAL 0,5, `fade_in_sec` REAL 0,5, `duck_curve` TEXT `equal_power`,
`duck_scope` TEXT `recorded` (anlamlar için bkz. [§5](#5-arka-plan-sesi-ducking-modu)).
`keep_background` tutulur ve `duck_mode='separated'` ile eşdeğerdir. iOS DB'si yeni olduğu için
sütunlar ilk şemada varsayılanlarıyla oluşturulur (Q3).

**`recordings` ek sütunları:** `source` TEXT DEFAULT `'mic'` (`'import'` olabilir),
`trim_start_sec` REAL 0, `trim_end_sec` REAL 0, `offset_sec` REAL 0 (ek olarak
`duration_sec`, `latency_comp_sec`, `sample_rate`).

Bayat take tespiti: Python `rendered_at` + `rendered_rec_count` sezgisi kullanır
(`app.py:2979-2997`); cue zamanı veya ses seviyesi değişimini kaçırır. Swift'te MixPlan
hash'i bunu kapsar ve ducking parametrelerini de içerir.

### Sandbox yerleşimi

| Yol | İçerik | Yedek |
|---|---|---|
| `Application Support/ChoosVoie/db.sqlite` (+wal) | DB | iCloud yedeğine dahil |
| `.../Media/videos/<uuid>.<ext>` | videolar | dahil (büyük; seçenek) |
| `.../Media/rec/<uuid>.caf` | LPCM 48 kHz mono (kayıt ve içe aktarılan ses) | dahil |
| `.../Media/bg/<video_uuid>.bg.m4a` + `bg/segcache/<hash>.caf` | arka plan + segment önbelleği (yalnız Pro) | hariç |
| `.../Outputs/<uuid>.mp4` | render çıktısı | dahil |
| `.../Models/` | WhisperKit / Core ML (Faz 2+) | `isExcludedFromBackup` |
| `Caches/wave/<video_uuid>.json` | dalga formu | önbellek |
| `tmp/render-<uuid>/`, `tmp/preview.caf` | ara dosyalar | silinir |

- **Neden CAF/LPCM:** AAC priming gecikmesi (birkaç on ms, Doğrulanmadı) senkronu ve
  ölçümü bozar; ≈96 KB/s, Python'daki 50 MB sınırı >8 dk'ya denk gelir.
- **JSON v1 / SRT uyumu:** JSON `{"app":"choos-voie","version":1,video_title,exported_at,cue_count,cues:[{start_sec,end_sec,text}]}`
  (`app.py:904-914`), sınır 1 MB / 500 cue (875-876). SRT `HH:MM:SS,mmm`, ayırıcı `,` veya
  `.`; metin satırları boşlukla birleşir (951-971). Biçimler birebir korunur;
  `exported_at` ISO saniye hassasiyetinde, saat dilimsiz. Python çıktısından altın test seti
  üretilir.
- **Ayırma imzası v2 (Pro):** Python imzası `sha256(json.dumps(sorted[(round(s,3), round(e,3))]))`,
  metin dahil değil (`app.py:2153-2157`). Swift'te `sha256("s_ms-e_ms;" sıralı tamsayı ms)`
  (CryptoKit), `bg_sig_version=2` — Swift `JSONEncoder` ondalık gösterimi farklı olabilir;
  imza dışarı çıkmadığı için byte uyumu gerekmez.
- Masaüstü DB/take/kayıt taşıma kapsam dışı (Q3); istenirse GRDB ile `choosvoie.db` salt
  okunur açılabilir.

---

## 10. Montajın AVFoundation karşılığı

Temel ilke: dışa aktarma `AVAudioMix`'e **bırakılmaz**. `MixPlan` (saf değer) iki yere gider:

1. `ExportRenderer`: blok tabanlı çevrimdışı mikser (ducking zarfı örnek başına uygulanır)
   → limiter → AAC → video passthrough birleştirme.
2. `PreviewComposer`: `AVMutableComposition` + `AVAudioMix` rampalarıyla gerçek zamanlı
   önizleme; limiter yok, kazanç ≤1'e kısılı, "önizleme" etiketli.

Gerekçe: `AVAudioMix` ses değeri aralığı 0,0–1,0'dır [V1, V2] — **>1 kazanç bu API ile
mümkün değil (doğrulandı)**; limiter yok; export preset'inin `audioMix`'i uyguladığı ve
rampa örnek hassasiyeti Doğrulanamadı. Genel AVFoundation bilgisi:
[ios.md §3.3](ios.md#33-montaj--avfoundation).

| # | Python (`app.py`) | iOS karşılığı | Belirsizlik |
|---|---|---|---|
| 1 | Orijinal × `bg_gain`, kaydı olan cue pencerelerinde 0 (2684-2685) | "bed": örnek × `bg_gain` × ducking zarfı (`vDSP_vmul`); zarf `DuckEnvelopeBuilder`'dan gelir, örnek hassas; `mute` = `duck(0, 0, 0)` ile Python paritesi | ffmpeg `enable` muhtemelen çerçeve düzeyi (~20 ms, Doğrulanmadı); parite testi `mute` modunda |
| 2 | `keep_background` + bg + ses → bg × `bg_gain` yalnız pencerelerde (2644-2647, 2688) | Pro `separated`: orijinal ↔ stem doğrusal çapraz geçiş, stem × (1 − zarf_doğrusal) | — |
| 3 | Ses yok → `anullsrc` + `-shortest` (2657-2661, 2728) | bed sessiz; süre = video | — |
| 4 | Kayıt `start_sec` kadar gecikir, kırpma yok (2693-2696) | `round(start_sec·48000) − latency_comp` konumuna; kırpma yok (Q4); sessizlik kırpma yıkıcı değil, `trim_*` ile ([§6](#6-ses-düzeltmeleri)) | `latency_comp` yeni; S0.3 |
| 5 | Kazanç `dub_master × rec_vol × auto`; bg 0–150, dub 0–200 (1952-1956, 2673-2679) | toplamadan önce `vDSP_vsmul` (>1 serbest) | `AVAudioMix` ile >1 mümkün değil (doğrulandı, [V1]) → export'ta kullanılmıyor, önizlemede ≤1'e kısılır |
| 6 | `amix normalize=0 duration=first` (2701) | düz toplama; uzunluk = bed | — |
| 7 | Limiter yalnız `max_gain>1` ise, 0,85 (≈−1,41 dBFS), 5/50 ms, `level=disabled` (2690-2711) | kendi look-ahead peak limiter'ımız (Accelerate); koşul genişler: `max_gain>1` veya `duck` + `depth>0` veya `separated` | `alimiter` ile birebir değil; kabul S0.2; alternatif `AUPeakLimiter` (`AVAudioUnitEffect`) iOS'ta Doğrulanmadı |
| 8 | AAC 192k + faststart (2727) | `AVAudioFile` AAC 192k veya `AVAssetWriter` | faststart ≈ `shouldOptimizeForNetworkUse` (Doğrulanmadı) |
| 9 | `-c:v copy` → `libx264` yedeği (2741-2743) | `AVMutableComposition` → `AVAssetExportPresetPassthrough`; olmazsa `HighestQuality` | `.webm`/VP9 Bilinmiyor; desteklenmezse içe aktarmada Türkçe hata |
| 10 | Başarıda eski çıktı silinir, hatada korunur (2578-2580, 2770-2777) | `tmp`'de üret → doğrula → DB `output_file` → eskiyi sil | — |
| 11 | Auto-level: `silenceremove(-50dB, 0.2s)` + `volumedetect`; −20 hedef, +15/−6, −1 tavan, −45 taban (1875-1908) | 20 ms pencere, −50 dBFS altı ≥0,2 sn at; RMS dB = 10·log10(mean(x²)); peak = max\|x\|; formül birebir | yaklaşık taklit; ±0,5 dB hedefi S0.2 |

Not: Python'da susturma yalnızca **kaydı olan** cue'larda uygulanır (`enable_expr`, 2684);
kaydı olmayan cue'da orijinal ses çalar. Bu davranış `duck_scope='recorded'` varsayılanı
olarak korunur. Bed kazancı orijinal ve bg için ortaktır (2685, 2688).

### Çevrimdışı mikser: A mı B mi?

Karar S0.2 sonrası verilir; varsayılan A.

| | A: kendi blok mikserimiz | B: `AVAudioEngine` manual rendering [A5] |
|---|---|---|
| Akış | `AVAssetReader` → vDSP → limiter → `AVAudioFile` | `scheduleBuffer(at:)` + motor çevrimdışı render |
| Artı | deterministik, test edilebilir; >1 kazanç, ducking zarfı, limiter tam kontrol; düşük bellek (1 sn blok) | zamanlama ve format dönüşümü hazır |
| Eksi | zamanlama/SRC kendimiz (birkaç yüz satır, tahmin) | >1 kazanç için EQ `globalGain` veya önceden ölçek; limiter yine kendimiz / `AUPeakLimiter` (Doğrulanmadı) |

---

## 11. Pro katmanı: API alternatifleri ve abonelik

Bu bölümün tamamı **Pro** katmanına (Faz 3) aittir; Normal katman bunların hiçbirini
kullanmaz. Fiyatlar 2026-11-15'te kaynak sayfalarından alınmıştır.

### LLM hızlı katmanı (1M token başına giriş/çıkış)

| Model | $ giriş/çıkış | Not | Kaynak |
|---|---|---|---|
| Anthropic `claude-haiku-5-5` | 0,10 / 0,50 (≤100K prompt); >100K 0,50 / 2,50; batch 0,05 / 0,25; cache okuma 0,01 | "Fastest", 1M bağlam | [P1, P2] |
| Google `gemini-3.1-flash-lite` | 0,25 (ses girişi 0,50) / 1,50 | | [P3] |
| Google `gemini-3.5-flash-lite` | 0,30 / 2,50 | | [P3] |
| Google `gemini-2.5-flash-lite` | 0,10 / 0,40 | | [P3] |
| Google `gemini-3.8-flash` | 0,75 / 3,75 → 2027-01-01'den itibaren 1,50 / 7,50 | | [P3] |
| OpenAI `gpt-5-nano` | 0,05 / 0,40 | | [P4] |
| OpenAI `gpt-5.4-nano` | 0,20 / 1,25 | | [P4] |
| OpenAI `gpt-5-mini` | 0,25 / 2,00 | | [P4] |
| OpenAI `gpt-5.4-mini` | 0,75 / 4,50 | | [P4] |
| Groq `openai/gpt-oss-20b` | 0,075 / 0,30 | 1000 tok/s | [P5] |
| Groq `gpt-oss-120b` | 0,15 / 0,60 | 500 tok/s | [P5] |
| Cerebras, Mistral Small | Doğrulanmadı | | — |

### Konuşma tanıma (STT) API'leri

Normal katman Apple `SpeechTranscriber` kullanır (ücretsiz, cihazda). Aşağıdakiler Pro'da
daha iyi/daha geniş dil kapsamı için bulut seçenekleridir.

| Hizmet | Fiyat | Not | Kaynak |
|---|---|---|---|
| Groq `whisper-large-v3-turbo` | $0,04/saat | 216× gerçek zaman; kelime + segment zamanı (`verbose_json`); 25 MB ücretsiz katman | [P5b] |
| Groq `whisper-large-v3` | $0,111/saat | 189× | [P5b] |
| OpenAI `gpt-4o-mini-transcribe` | $0,003/dk | kelime zamanı: Doğrulanmadı | [P4] |
| OpenAI `gpt-transcribe` | $0,0045/dk | | [P4] |
| OpenAI `gpt-4o-transcribe` | $0,006/dk | | [P4] |
| OpenAI `whisper` | $0,006/dk | | [P4] |
| Deepgram Nova-3 | $0,0043/dk mono, $0,0052/dk çok dilli | $200 ücretsiz kredi | [P7] |
| AssemblyAI Universal-3.5 Pro | $0,21/saat | konuşmacı ayrımı +$0,02/saat | [P11] |
| AssemblyAI Universal-2 | $0,15/saat | | [P11] |
| ElevenLabs Scribe v3 | $0,20/saat | | [P6] |
| Google Chirp | Doğrulanmadı | | — |

### Ayırma, ses temizleme ve TTS API'leri

| Hizmet | Fiyat | Not | Kaynak |
|---|---|---|---|
| Music.AI (dialogue/music/effects) | $0,05/dk | arka plan stem'ini doğrudan verir (Pro `separated`) | [P8] |
| ElevenLabs Voice Isolator | $0,12/dk | yalnız ses (arka plan değil); öneri: kullanıcının kendi kaydını temizlemek için | [P6] |
| Replicate Demucs | ~$0,017/çalıştırma | T4, ~75 sn; Music.AI yedeği | [P12] |
| LALAL.AI, AudioShake | Doğrulanmadı | | [P9, P10] |
| ElevenLabs TTS | Flash $0,04 / v4 $0,08 (1K karakter) | | [P6] |
| Deepgram Aura-2 | $0,030/1K karakter | | [P7] |
| OpenAI `gpt-4o-mini-tts` | $0,60 metin girişi / $12 ses çıkışı (1M token) | | [P4] |

### Örnek maliyet (10 dk video, Pro)

| Kalem | Tutar |
|---|---|
| Groq turbo STT | ≈$0,007 |
| Music.AI ayırma | $0,50 |
| Haiku 5.5 ile cue temizliği | <1 sent (≈3K giriş + 3K çıkış varsayımı, ölçülmedi) |

### LLM bu uygulamada ne işe yarar?

Mevcut uygulama LLM'e **ihtiyaç duymaz**; aşağıdakilerin hepsi opsiyoneldir ve MVP'de yoktur.

| Özellik | Birinci tercih | Yedek | Not |
|---|---|---|---|
| Transkript segmentlerini seslendirilebilir cue'lara bölme + noktalama | Foundation Models `@Generable` (cihazda, ücretsiz) [A6]; Türkçe destekli [A8] | bulut hızlı katman | Bağlam penceresi belgesiz [A6] → 20–40 cue'luk parçalar; zaman damgasını LLM üretmez, yalnız birleştir/böl kararı verir; zaman kelime damgalarından gelir |
| Cue çevirisi | Translation framework [A9]; Türkçe/cihaz durumu çalışma zamanında kontrol | Foundation Models → bulut | LLM çeviri iddiası yok |
| Telaffuz geri bildirimi | kaydı yeniden transkribe et + deterministik fark | LLM yalnızca açıklar | — |
| Başlık / özet | Foundation Models | — | düşük değer |

| Model | $/1M giriş/çıkış | Çağrı başı (3K+3K, varsayım) | Rol |
|---|---|---|---|
| `claude-haiku-5-5` [P1, P2] | 0,10 / 0,50 | ≈$0,0018 | Birincil; 1M bağlam, tüm cue listesi tek çağrıda; Türkçe kalitesi ölçülmedi |
| `gpt-5-nano` [P4] | 0,05 / 0,40 | ≈$0,00135 | maliyet alternatifi |
| `gemini-2.5-flash-lite` [P3] | 0,10 / 0,40 | ≈$0,0015 | alternatif |
| Groq `gpt-oss-20b` [P5] | 0,075 / 0,30 | ≈$0,0011 | gecikme öncelikli (1000 tok/s) |

### Abonelik: StoreKit 2 ve IAP kuralları

| Konu | Karar / kural | Kaynak |
|---|---|---|
| Ödeme yöntemi | Özellik veya abonelik kilidi açmak için uygulama içi satın alma (IAP) zorunlu (3.1.1) | [R1] |
| Abonelik süresi | en az yedi gün; kullanıcının tüm cihazlarında kullanılabilir (3.1.2(a)); örnekler arasında "cloud support", "SAAS" geçer | [R1] |
| Abonelik öncesi açıklama | kullanıcıya ne alacağı net anlatılmalı (3.1.2(c)) | [R1] |
| Bulut paylaşımı | üçüncü taraf yapay zekâ dahil paylaşımda açık izin (5.1.2(i)); ilk kullanımda onay ekranı. Kurallar son güncelleme 2026-10-16 | [R1] |
| API | `Product`, `Transaction`, `Transaction.currentEntitlements`, `Transaction.updates` (iOS 15.0+); `updates` dinleyicisi açılışta bir `Task`'ta başlatılır | [V12] |
| Hazır ekran | `SubscriptionStoreView` (iOS 17.0+): grup/ürün kimlikleri, şartlar ve gizlilik düğmeleri | [V13] |
| Sunucuda doğrulama | App Store Server API / imzalı işlem: Doğrulanmadı | — |
| Dakika kredisi alternatifi | Doğrulanmadı (Q11) | — |

### Onay ve anahtar yönetimi

- **Onay (Kural 5.1.2(i)):** Ses veya metin bulut LLM/STT/ayırma hizmetine gidiyorsa
  kullanıcıdan açık onay alınmalıdır [R1]. Bulut özellikleri varsayılan KAPALI, ilk
  kullanımda onayla açılır. Normal katmanda ağ olmadığı için bu kapı devreye girmez.
- **Proxy:** API anahtarları uygulamada tutulamaz; bulut kullanımı ince bir proxy backend'den
  geçer (auth, aboneliğin sunucuda doğrulanması, kullanıcı başı günlük dakika tavanı,
  kill switch). Kill switch Pro bulut özelliklerini kapatır, aboneliği (entitlement) korur.
- **Bulut STT yedeği:** Groq `whisper-large-v3-turbo` ($0,04/saat, kelime + segment
  zamanı, 25 MB ücretsiz katman) [P5b]; 16 kHz mono sıkıştırılmış gönderim, gerekirse parçalama.

---

## 12. Yol haritası

### Faz 0 — doğrulama spike'ları (ölçüm raporu)

Çıkış değerleri hedef varsayımdır; ölçümle kesinleşir.

| Spike | Ölçüm | Çıkış kriteri |
|---|---|---|
| S0.1 STT (İngilizce) | `supportedLocale(equivalentTo:)` ile en-US; varlık indirme (`AssetInventory`); dosyadan analiz; İngilizce test videosunda RTF, kelime/segment sınır hatası, cue bölme | medyan sınır ≤250 ms, RTF ≤0,5; dosya yolu çalışmazsa `AVAudioFile` ile tamponlu besleme |
| S0.2 Mix paritesi | `mute` modunda Python ile karşılaştırma + zarf birim testleri + limiter koşulu: hizalama, cue RMS farkı, auto-level dB farkı, tepe, AAC sonrası 0 dBFS oranı | hizalama ≤1 ms; RMS ≤0,5 dB; 0 dBFS ≤ Python (38/2,4M, `app.py:2708-2709`); mikser A/B seçimi |
| S0.3 Kayıt gecikmesi + voice processing | `inputLatency` + `outputLatency` + `ioBufferDuration` vs alkış/loopback; voice processing açık/kapalı (AGC açık/kapalı) A/B dinleme; varsayılanı belirler | telafi sonrası ≤20 ms |
| S0.4 Ayırma | Faz 3 (Music.AI) ve Faz 4 (Core ML Demucs) kapsamına taşındı | — |
| S0.5 İçe aktarma | video biçimleri (mp4/mov/m4v/webm oynatma + passthrough) + ses dosyası → CAF (m4a/mp3/wav, DRM) | desteklenen biçim listesi, hata metinleri |
| S0.6 Arka plan / süre | 10 dk take render süresi + önizleme render süresi; arka plana atma; BG API'leri | ≤60 sn; kurtarma çalışıyor |
| S0.7 Ducking dinleme | 5 klip (konuşma ağırlıklı, müzik ağırlıklı, ambiyans, hızlı diyalog, kısa boşluklu cue) × fo/fi {0,25 / 0,5 / 1,0} × derinlik {0 / 15 / 25} × {linear / equal_power}; kör A/B; mute ile karşılaştırma | varsayılanlar onaylanır/değişir; ≥4/5 klipte duck > mute tercih edilmezse sıradaki adım (Light spike) |
| S0.8 Önizleme rampası | `setVolumeRamp` doğrusallığı, rampa sayısı, seek doğruluğu, export ile RMS farkı; 3 export preset'inin (Passthrough, AppleM4A, HighestQuality) `audioMix` uygulayıp uygulamadığı; üst üste binen rampa testi | fark ≤1 dB, değilse önizleme render'ı |

### Fazlar

| Faz | Kapsam | Bağımlılık | Başarı |
|---|---|---|---|
| 1 — Normal (MVP) | içe aktarma, kütüphane, cue editörü (timeline + tutamak), toplu kaydırma, JSON/SRT, dalga formu, İngilizce otomatik cue + aralık transkripsiyonu, kayıt + dosyadan ses içe aktarma, ses düzeltmeleri 1–7, take mikseri, mute/duck, önizleme, render, dışa aktarma | S0.1, S0.2, S0.3, S0.7, S0.8 | uçtan uca akış; 10 altın take (mute) parite; zarf birim testleri %100; render ≥%99 |
| 2 — Türkçe | `supportedLocale(equivalentTo:)` ile cihazda Türkçe kontrolü; Apple destekliyorsa `SpeechTranscriber`, desteklemiyorsa WhisperKit (tr); motor seçimi | S0.1-tr | medyan sınır ≤250 ms, RTF ≤0,5 |
| 3 — Pro | StoreKit 2 (+ `SubscriptionStoreView`), `EntitlementProvider`, `Transaction.updates` dinleyicisi, proxy (auth, tavan, kill switch, sunucuda abonelik doğrulama), onay ekranı, Music.AI `separated`, Groq/Deepgram STT, segment önbelleği | Q1 = App Store, Q2 = evet | bulut iş başarısı ≥%99, tavan aşılmaz, abonelik düşünce Normal kesintisiz |
| 4 | Core ML Demucs, çeviri, telaffuz geri bildirimi, YouTube IFrame ile indirmesiz dublaj ([ios.md §4](ios.md#4-youtube-ve-app-store-kuralları)), iCloud (gerekirse SwiftData yeniden değerlendirilir) | ayırma spike'ı | — |

Pro'da segment önbelleği sayesinde yalnız değişen segmentler yeniden işlenir (Python hepsini
işler) → bulut maliyeti düşer.

**Geriye uyum:** iOS DB'si yeni olduğundan ducking sütunları ilk şemada varsayılanlarla
gelir (Q3); `keep_background` tutulur ve `duck_mode='separated'` ile eşdeğerdir; JSON v1/SRT
birebir.

**Geri alma:** duck → mute feature flag + take ayarı; önizleme rampası → önizleme
render'ı; Pro kill switch + entitlement kapatma (Normal etkilenmez); her motor feature flag
arkasında; migration öncesi `db.sqlite` yedeği; çıktılar atomik.

### Gözlemlenebilirlik ve hedefler

- Log: `os.Logger` (alt sistem kategorileri). `[montaj]`: mode, depth, fo, fi, curve, scope,
  merged_windows, limiter_reason (Python'daki `[montaj]`/`[seviye]` çıktılarının karşılığı);
  `[duzeltme]`: trim_start, trim_end, latency_comp, auto_gain_db; `[stt]`: motor, locale, RTF;
  kişisel veri yok.
- İzleme: `OSSignposter` (zarf, blok mikser, limiter, kodlama, önizleme render, STT, dosya
  dönüşümü); metrik: MetricKit + yerel sayaç (çökme, bellek tepe, termal, iş süreleri);
  Pro: proxy logu (dakika, maliyet, hata, tavan), IAP dönüşümü, `AssetInventory` durumu.
- Hedefler (varsayım, Faz 0'da kesinleşir): render başarısı ≥%99; 10 dk take render ≤60 sn
  (iPhone 17); STT (İngilizce) RTF ≤0,5; cue sınırı medyan ≤250 ms; kayıt senkronu ≤20 ms;
  zarf ±1 örnek; önizleme–export RMS farkı ≤1 dB (zamanlama ≤1 kare); çökmesiz oturum
  ≥%99,5; Pro bulut iş başarısı ≥%99; Pro ayırma p95 ≤2× ses süresi.

### Riskler

O = olasılık, E = etki (Y yüksek / O orta / D düşük).

| Risk | O/E | Azaltma |
|---|---|---|
| Ducking yetersiz (ambiyans kaybı, pompalanma) | O/Y | S0.7; kısmi derinlik; `minRecoverSec`; sıradaki adımlar ([§5](#5-arka-plan-sesi-ducking-modu)) |
| Kısmi derinlikte konuşma sızar | Y/O | varsayılan 0; arayüz açıklaması; Pro `separated` |
| Önizleme/export farkı | O/O | S0.8; önizleme render'ı |
| Kısmi derinlikte limiter tetiklenmez → taşma | O/D | genişletilmiş limiter koşulu |
| SpeechTranscriber segmentleri cue'ya uygun değil | O/O | kelime zamanından kendi bölücümüz; editörde ince ayar |
| SpeechTranscriber İngilizce/cihaz desteği beklenenden dar | D/Y | çalışma zamanında kontrol; `DictationTranscriber` yedeği [V11]; WhisperKit (İngilizce) |
| Türkçe kullanıcı MVP'de otomatik cue alamaz | Y/O | elle cue + JSON/SRT; Faz 2 |
| WhisperKit Türkçe zaman kayması / yavaşlık (Türkçe Apple'da yoksa) | O/Y | S0.1-tr; Groq yedeği (Pro); cue editöründe hızlı ince ayar |
| Kayıt gecikmesi → senkron kayması | O/Y | S0.3, `latency_comp_sec`, kullanıcı ofseti |
| Voice processing tınıyı bozar (AGC/EQ) | O/O | varsayılan kapalı; aç/kapa anahtarı, kulaklık önerisi; S0.3 |
| İçe aktarılan ses DRM'li/desteksiz | O/D | net hata mesajı |
| Limiter farkı → AAC'de 0 dBFS taşması | O/D | S0.2'de kabul; eşik ayarı (0,85 üstü yok) |
| Uzun iş arka planda öldürülür | Y/O | idempotent/devam ettirilebilir; açılışta kurtarma; BG API Doğrulanmadı (S0.6) |
| `.webm` desteklenmez | Y/D | içe aktarmada net mesajla red |
| Core ML Demucs olmaz | Y/O | Pro bulut ayırma; Normal bağımsız (Faz 4) |
| Pro: IAP incelemesi, backend işletme yükü | O/Y | Pro ayrı fazda |
| Bulut maliyet kaçışı (Pro) | D/Y | proxy'de kullanıcı başı günlük dakika tavanı; kill switch |
| App Store reddi (5.2.3, 5.1.2(i), 3.1.1) | D/Y | YouTube indirme yok; onay yalnız Pro; Pro yalnız IAP; gizlilik etiketi |
| GRDB bağımlılığı | D/O | repository arayüzü değiştirilebilir |

Olumsuz sonuçlar (kabul edilen): Normal'de cue içinde ambiyans/müzik kaybı (derinlik 0);
kısmi derinlik konuşma sızdırır; MVP'de Türkçe otomatik cue yok (elle çalışır);
önizleme/export eğri farkı olabilir; limiter/auto-level ffmpeg ile birebir değil (tolerans);
WhisperKit model indirme/yer (Faz 2; boyut Doğrulanmadı); Pro'da proxy işletme yükü.

---

## 13. Açık sorular

Varsayımlar belirtilen yönde ilerlenir; cevaplar kararı değiştirebilir.

| # | Soru | Varsayım / etki |
|---|---|---|
| Q1 | Dağıtım App Store mu, kişisel kullanım mı? | AÇIK. Yalnız kişisel ise Pro anlamsız ([§4](#kararı-ne-değiştirir)) |
| Q2 | Proxy backend işletilebilir mi? | Yalnız Pro için gerekir; Normal etkilenmez |
| Q3 | Masaüstü take/kayıtları taşınacak mı? | Hayır; yalnız JSON v1/SRT |
| Q4 | Cue'yu aşan kayıt kırpılsın mı? (Bugün kırpılmıyor, `app.py:2696`) | Parite: hayır |
| Q4b | Duck cue bitişinde mi, klip sonunda mı biter? İçe aktarılan dosya için süre sınırı? | Cue bitişi; ≤ cue süresi + 10 sn önerisi; S0.7 |
| Q6 | YouTube altyazısından otomatik cue korunacak mı? | App Store'da 5.2.3 sorunu; kişisel sürümde bayrak olabilir |
| Q7 | `.webm` desteği gerekli mi? | Bilinmiyor; S0.5 ölçer, desteklenmezse içe aktarmada red |
| Q10 | Yeni take varsayılanı: duck / derinlik 0 / auto-level açık? | Evet / 0 / açık (öneri) |
| Q11 | Pro fiyat modeli abonelik mi, dakika kredisi mi? | Abonelik; kredi alternatifi Doğrulanmadı |
| Q12 | Arayüz dili TR / EN / ikisi? | Bugün TR; STT dilinden bağımsız |

Karara bağlananlar: minimum iOS sürümü 26 (SpeechAnalyzer [V6], Foundation Models [A6]);
Normal'de Light ayırma yok; Türkçe motor karşılaştırması Faz 2'ye taşındı (S0.1-tr).

**Doğrulanmadı listesi (Faz 0'da kapatılacaklar):**

- Ses / montaj: üst üste binen rampa davranışı; `AVAssetExportPresetPassthrough`'un
  `audioMix` uygulaması; rampa doğrusallığı, örnek hassasiyeti, rampa sayısı sınırı, seek
  sonrası doğruluk (S0.8); `AUPeakLimiter` iOS'ta; faststart karşılığı; AAC priming
  gecikmesi; ffmpeg `enable` çerçeve hassasiyeti; `AVAudioUnitEQ` ile high-pass; tap thread'i.
- Konuşma tanıma: `SpeechTranscriber` İngilizce ve Türkçe desteği (çalışma zamanında
  `supportedLocale(equivalentTo:)`); desteklenen cihaz listesi; WhisperKit model boyutları.
- Kayıt: voice processing'in gürültü bastırma yapıp yapmadığı; dosyada gürültü azaltma için
  Apple API'si (yokluğu kanıtlanmadı); DRM'li ses içe aktarma; `.webm`.
- Sistem: arka plan çalıştırma API'leri; Fotoğraflar'a yazma izni; `AVAssetImageGenerator`
  küçük resimleri; Local Network izni anahtarı.
- Veri / LLM: SwiftData `#Unique`/CloudKit ayrıntıları; GRDB sürüm/lisans; Foundation Models
  bağlam penceresi; Translation framework Türkçe/cihazda; Türkçe Personal Voice.
- Pro: App Store Server API / imzalı işlem ile sunucuda abonelik doğrulama; dakika kredisi
  modeli; Core ML Demucs hız/boyut/bellek.

**Bu belgede doğrulananlar:** `AVAudioMix` rampaları ve 0–1 aralığı [V1, V2]; önizleme ve
dışa aktarmada `audioMix` [V3, V4]; `SpeechAnalyzer` dosya girdisi, zaman damgası, cihazda
çalışma ve `AssetInventory` [V7, V8, V9, V10]; StoreKit 2, `SubscriptionStoreView`, IAP
zorunluluğu (3.1.1) ve 3.1.2(a)/(c) [V12, V13, R1]; voice processing = yankı engelleme +
AGC [V14, V15]; `fileImporter`/`UTType.audio` [V16]; `PhotosPicker`, `VideoPlayer`;
Liquid Glass [V17].

---

## 14. Çekirdek protokoller

> TASLAK — derlenmedi; isimler ve imzalar öneridir.

```swift
// TASLAK — derlenmedi; isimler ve imzalar öneridir.
public struct TimeRange: Sendable, Hashable, Codable { public var start: Double; public var end: Double }
public struct TranscriptSegment: Sendable { var range: TimeRange; var text: String; var words: [(String, TimeRange)]? }

public enum EngineAvailability: Sendable { case ready, needsDownload(bytes: Int64?), unsupported }

public protocol TranscriptionEngine: Sendable {
    var id: String { get }                       // "apple.speechtranscriber", "whisperkit.small", "cloud.groq"
    var requiresNetwork: Bool { get }
    func availability(for locale: Locale) async -> EngineAvailability   // Apple: supportedLocale(equivalentTo:) ile
    func transcribe(audio: URL, range: TimeRange?, locale: Locale)
        -> AsyncThrowingStream<TranscriptionEvent, Error>   // .progress(Double) / .segment(TranscriptSegment)
}

public enum SeparationMethod: String, Codable, Sendable { case light, companion, cloud, coreml }
// Normal'de light ve companion kullanılmaz; companion yalnız geliştirici bayrağı.

public protocol SeparationEngine: Sendable {
    var method: SeparationMethod { get }
    var requiresNetwork: Bool { get }            // true ise ConsentGate'ten geçmek zorunlu
    func canHandle(_ info: AudioTrackInfo) async -> Bool   // light: yalnızca stereo
    /// Tek bir birleşik segment için arka plan (no_vocals) üretir.
    /// Birleştirme, süre kontrolü ve atomik değiştirme ortak StemAssembler'da yapılır.
    func separateSegment(source: URL, range: TimeRange, into out: URL) async throws
}

public enum Tier: Sendable { case normal, pro }
public protocol EntitlementProvider: Sendable { func currentTier() async -> Tier }   // StoreKit 2

public struct EngineRegistry: Sendable {
    let transcription: [any TranscriptionEngine]; let separation: [any SeparationEngine]
    let entitlements: any EntitlementProvider; let consent: ConsentGate
    /// Ağ gerektiren motor yalnız .pro + onay varsa listelenir.
    public func usableTranscription(for locale: Locale) async -> [any TranscriptionEngine]
    public func usableSeparation() async -> [any SeparationEngine]
}

public enum FadeCurve: String, Codable, Sendable { case equalPower, linear, sCurve }
public enum DuckScope: String, Codable, Sendable { case recordedCues, allCues }
public struct DuckSettings: Sendable, Hashable, Codable {
    var level: Float          // 0...1, cue içinde kalan (duck_depth/100)
    var fadeOut: Double       // sn, cue başında biter
    var fadeIn: Double        // sn, cue sonunda başlar
    var curve: FadeCurve; var scope: DuckScope
    var minRecoverSec: Double = 0
    static let `default` = DuckSettings(level: 0, fadeOut: 0.5, fadeIn: 0.5, curve: .equalPower, scope: .recordedCues)
    static let hardMute  = DuckSettings(level: 0, fadeOut: 0, fadeIn: 0, curve: .linear, scope: .recordedCues)
}

public enum BackgroundTreatment: Sendable, Hashable, Codable {
    case hardMute                                  // = duck(level 0, fo 0, fi 0) — Python paritesi
    case duck(DuckSettings)
    case separated(stem: URL, crossfade: DuckSettings)   // yalnız Pro; level yok sayılır
}

public struct GainKeyframe: Sendable, Hashable { var sample: Int64; var gain: Float; var curveToNext: FadeCurve? } // nil = sabit
public struct DuckEnvelope: Sendable, Hashable {
    var keyframes: [GainKeyframe]                 // DuckEnvelopeBuilder üretir; 0...1
    func fill(_ out: UnsafeMutableBufferPointer<Float>, startingAt sample: Int64)
}

public struct MixPlan: Sendable, Hashable {      // saf; hash'i takes.rendered_plan_hash'e yazılır
    public struct Clip: Sendable, Hashable { var file: URL; var startSample: Int64; var trimStart: Int64; var trimEnd: Int64; var gain: Float }
    var bedGain: Float                           // bg_volume/100, orijinal ve bg için ortak
    var treatment: BackgroundTreatment           // muteWindows + backgroundFile'ın yerine
    var envelope: DuckEnvelope                   // treatment'tan türetilir, hash'e dahil
    var clips: [Clip]                            // dub_master × rec_vol × auto
    var limiter: LimiterSpec?                    // max_gain>1 || duck(level>0) || separated (0.85, 5 ms, 50 ms)
    var durationSamples: Int64; var sampleRate: Double = 48_000
}

public protocol TakeRenderer: Sendable {
    func render(_ plan: MixPlan, video: URL, output: URL) -> AsyncThrowingStream<RenderEvent, Error>
}

public enum AutoLevel {                          // app.py:1875-1908 ile birebir
    static let target = -20.0, maxBoost = 15.0, maxCut = -6.0, peakCeil = -1.0, floor = -45.0
    static func gain(meanDB: Double?, peakDB: Double?) -> Double {
        guard let m = meanDB, m > floor else { return 1 }
        var g = max(maxCut, min(maxBoost, target - m))
        if let p = peakDB { g = min(g, peakCeil - p) }
        return pow(10, g / 20)
    }
}

public actor JobCoordinator {                    // ağır işler seri çalışır; durum DB'de kalıcı
    public func enqueue(_ job: Job) -> AsyncThrowingStream<JobEvent, Error> { /* … */ fatalError() }
    public func recoverInterruptedJobs() async { /* rendering/separating → error("Yarıda kesildi") */ }
}
```

---

## Kaynaklar

2026-11-15'te kontrol edildi. Bu belgedeki `[R1]`, `[A1]`, `[V1]` … etiketleri aşağıya bağlanır;
ios.md'nin kendi kaynakları için bkz. [ios.md Kaynaklar](ios.md#kaynaklar).

**Apple kuralları ve dokümanları**

- [R1] [App Store İnceleme Kuralları](https://developer.apple.com/app-store/review/guidelines/)
- [A1] [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [A2] [SpeechTranscriber.ResultAttributeOption](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption)
- [A3] [SpeechTranscriber.supportedLocales](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales)
- [A4] [setVoiceProcessingEnabled(_:)](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:))
- [A5] [enableManualRenderingMode(_:format:maximumFrameCount:)](https://developer.apple.com/documentation/avfaudio/avaudioengine/enablemanualrenderingmode(_:format:maximumframecount:))
- [A6] [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [A7] [Foundation Models: diller ve yerel ayarlar](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [A8] [Apple Intelligence destek sayfası](https://support.apple.com/en-us/121115)
- [A9] [Translation](https://developer.apple.com/documentation/translation)
- [A10] [requestPersonalVoiceAuthorization](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/requestpersonalvoiceauthorization(completionhandler:))

**Apple dokümanları ve oturumları (ikinci doğrulama turu, 2026-11-15)**

- [V1] [setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)](https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters/setvolumeramp(fromstartvolume:toendvolume:timerange:))
- [V2] [setVolume(_:at:)](https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters/setvolume(_:at:))
- [V3] [AVPlayerItem.audioMix](https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix)
- [V4] [AVAssetExportSession.audioMix](https://developer.apple.com/documentation/avfoundation/avassetexportsession/audiomix)
- [V5] [AVAssetReaderAudioMixOutput](https://developer.apple.com/documentation/avfoundation/avassetreaderaudiomixoutput)
- [V6] [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [V7] [SpeechAnalyzer.start(inputAudioFile:finishAfterFile:)](https://developer.apple.com/documentation/speech/speechanalyzer/start(inputaudiofile:finishafterfile:))
- [V8] [SpeechTranscriber.Preset](https://developer.apple.com/documentation/speech/speechtranscriber/preset)
- [V9] [WWDC25 oturum 277](https://developer.apple.com/videos/play/wwdc2025/277/)
- [V10] [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [V11] [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)
- [V12] [Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates)
- [V13] [SubscriptionStoreView](https://developer.apple.com/documentation/storekit/subscriptionstoreview)
- [V14] [AVAudioSession.Mode.voiceChat](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat)
- [V15] [AVAudioInputNode](https://developer.apple.com/documentation/avfaudio/avaudioinputnode)
- [V16] [UTType.audio](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/audio)
- [V17] [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

**Açık kaynak projeler**

- [G1] [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [G2] [Whisper](https://github.com/openai/whisper)
- [G3] [Demucs](https://github.com/facebookresearch/demucs)

**Fiyat ve ürün sayfaları**

- [P1] [Claude modelleri](https://platform.claude.com/docs/en/about-claude/models/overview)
- [P2] [Claude fiyatlandırma](https://platform.claude.com/docs/en/about-claude/pricing)
- [P3] [Google AI Studio fiyatlandırma](https://aistudio.google.com/docs/pricing)
- [P4] [OpenAI fiyatlandırma](https://developers.openai.com/api/docs/pricing)
- [P5] [Groq modeller](https://console.groq.com/docs/models)
- [P5b] [Groq konuşmadan yazıya](https://console.groq.com/docs/speech-to-text)
- [P6] [ElevenLabs API fiyatları](https://elevenlabs.io/pricing/api)
- [P7] [Deepgram fiyatlandırma](https://deepgram.com/pricing)
- [P8] [Music.AI fiyatlandırma](https://music.ai/pricing/)
- [P9] [LALAL.AI API](https://www.lalal.ai/api/)
- [P10] [AudioShake](https://www.audioshake.ai/)
- [P11] [AssemblyAI fiyatlandırma](https://www.assemblyai.com/pricing)
- [P12] [Replicate Demucs](https://replicate.com/cjwbw/demucs)
