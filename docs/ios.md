# Choos Voie'yi iPhone'da çalıştırma — değerlendirme ve yol haritası

Bu belge, Choos Voie'nin iPhone'da (örnek hedef: iPhone 17, iOS 26/27) çalıştırılıp
çalıştırılamayacağına dair yapılan değerlendirmeyi, iOS'ta hazır bulunan araçları ve
App Store kurallarının getirdiği sınırları özetler. Henüz bir iOS uygulaması yoktur; bu
bir planlama belgesidir.

> Araştırma internet aramasıyla yapılmıştır. "Doğrulanmadı" diye işaretlenen maddeler
> üçüncü taraf kaynaklardan gelir ve geliştirmeye başlamadan önce Apple'ın kendi
> dokümanlarından kontrol edilmelidir.

> Ayrıntılı Swift mimarisi, API alternatifleri ve yol haritası: [ios-swift-mimari.md](ios-swift-mimari.md)

## 1. Mevcut uygulama iPhone'da olduğu gibi çalışır mı?

**Hayır.** Sorun donanım değil, uygulamanın yapısı:

- Uygulama bir Python sunucusudur (FastAPI). iOS'ta PyTorch / Demucs `pip` ile kurulamaz.
- ffmpeg ve yt-dlp ayrı süreç olarak çalıştırılır (`app.py` içindeki `subprocess.run`
  çağrıları). iOS, uygulamaların başka program başlatmasına izin vermez.
- Pyto, a-Shell gibi iPhone'da Python çalıştıran uygulamalar torch/demucs desteklemez.

**Donanım yeterli mi?** Evet. Whisper "small" ve Demucs benzeri modeller iPhone'larda
çalışabiliyor (App Store'da bunu telefonda yapan uygulamalar var); montaj ise hafif bir iş.

## 2. Seçenekler

### Seçenek A — Sunucu bilgisayarda, kullanım iPhone'da (en kısa yol)

Uygulama Mac/PC'de çalışır, iPhone'dan aynı ağ üzerinden Safari ile açılır. Ağır işleri
bilgisayar yapar, mikrofon kaydı iPhone'da olur.

- Sunucu `python -m uvicorn app:app --host 0.0.0.0` ile başlatılmalı.
- Mikrofon `localhost` dışında **HTTPS** ister (bkz. README → Bilinen sınırlar).
  `mkcert` ile yerel sertifika veya `tailscale serve` kullanılabilir.
- Safari: `templates/dub.html` webm desteklenmezse `audio/mp4`'e düşüyor, ancak Safari'de
  test edilmedi; küçük düzeltmeler ve dokunmatik / dar ekran uyumu gerekebilir.

### Seçenek B — Yerel (native) iOS uygulaması, Swift ile

Her şey telefonda çalışır. Mac + Xcode gerekir. Aşağıdaki tablo mevcut parçaların
iOS karşılıklarını gösterir.

| Mevcut parça | iOS karşılığı | Durum |
|---|---|---|
| Whisper (transkripsiyon, otomatik replik) | `SpeechAnalyzer` / `SpeechTranscriber` | Hazır, cihaz üzerinde |
| Demucs (ses ayırma) | Modeli Core AI / Core ML'e çevirmek | Hazır API yok, yapılabilir |
| ffmpeg montaj | AVFoundation | Hazır |
| Mikrofon kaydı, dalga formu | AVAudioEngine | Hazır |
| YouTube indirme | — | App Store'da olmaz (bkz. bölüm 3) |

## 3. iOS'ta hazır araçlar

### 3.1 Konuşmayı yazıya çevirme — SpeechAnalyzer (iOS 26+)

Siri ve dikte özelliğinin kullandığı yeni Apple konuşma tanıma motoru.

- Tamamen cihaz üzerinde çalışır, internet gerektirmez.
- `attributeOptions: [.audioTimeRange]` ile **kelime düzeyinde zaman damgası** verebilir;
  replik başlangıç/bitiş zamanlarının otomatik çıkarılması için kritik. *(Doğrulanmadı.)*
- Dil modeli ilk kullanımda `AssetInventory` ile indirilir.
- **Açık sorular / eksikler:**
  - Türkçe desteği kontrol edilmeli.
  - Konuşmacı ayrımı (diarization) yok; iOS 27'de de duyurulmamış görünüyor.
  - Kelime zamanları birkaç yüz milisaniye kayabiliyor; gerekirse bir düzeltme katmanı
    (ör. Align projesi) eklenebilir. *(Doğrulanmadı.)*

### 3.2 Konuşmayı arka plandan ayırma

- **Herhangi bir videoda çalışan hazır Apple API'si bulunamadı.**
- **Audio Mix / `AUAudioMix` (iOS 26):** konuşmayı ortam sesinden ayırabiliyor, ancak
  yalnızca iPhone'un kendi çektiği uzamsal ses (spatial audio) kayıtlarında çalışır;
  dışarıdan gelen videolarda işe yaramaz.
- **Önerilen yol:** Demucs benzeri bir modeli cihaza çevirmek. iOS 27 ile gelen **Core AI**
  PyTorch modellerini Apple silikona çevirecek araçlarla geliyor; Core ML de
  desteklenmeye devam ediyor.
- **Normal katman (MVP) ayırma yapmaz:** bunun yerine fade'li ducking kullanır; bkz.
  [Arka plan sesi: ducking modu](ios-swift-mimari.md#5-arka-plan-sesi-ducking-modu).

### 3.3 Montaj — AVFoundation

`AVMutableComposition` + `AVAudioMix` ile video ve replik kayıtları birleştirilir, replik
başına ses seviyesi ve arka plan seviyesi ayarlanır, sonuç mp4 olarak dışa aktarılır.
Mevcut `dub_volume`, `bg_volume` ve `recordings.volume` ayarlarının karşılığı burada
uygulanabilir.

### 3.4 Kayıt — AVAudioEngine

- Anlık dalga formu ve seviye çubuğu.
- Ses işleme (voice processing) modu yankıyı engeller; böylece kayıt sırasında video sesi
  kulaklıksız da açık tutulabilir.

## 4. YouTube ve App Store kuralları

- **App Store İnceleme Kuralları 5.2.3:** YouTube, Vimeo, SoundCloud gibi üçüncü taraf
  kaynaklardan izinsiz medya indirmeyi, kaydetmeyi veya dönüştürmeyi yasaklar.
- **YouTube Kullanım Şartları** da indirmeyi yasaklar (yalnızca YouTube'un kendi
  çevrimdışı özelliği hariç).
- Sonuç: App Store sürümünde YouTube indirme özelliği **olamaz**.

### İzin verilen yollar

1. **Kullanıcının kendi videoları** — Fotoğraflar (`PHPickerViewController`) veya
   Dosyalar'dan seçim. Ana yol bu olmalı.
2. **İndirmeden YouTube'a dublaj** — resmi YouTube IFrame Player gömülür; kullanıcı
   video oynarken replik replik kayıt yapar, dinlerken dublaj videoyla eş zamanlı çalınır.
   YouTube içeren bir mp4 dışarı verilemez, yalnızca uygulama içinde "dublajlı izle"
   olur. YouTube'un geliştirici kuralları ayrıca incelenmeli.
3. Kullanıcının kendi ekran kaydını yüklemesi teknik olarak mümkün, ancak telif
   sorumluluğu kullanıcıya geçer; uygulama bunu önermemeli.

### Telif ve kullanıcı içeriği

- Kullanıcının yüklediği videoda telifli içerik olabilir.
- Uygulama yalnızca cihazda montajlayıp kaydediyorsa sorun azdır.
- Uygulama içi **paylaşım / topluluk** eklenirse Kural 1.2 gereği şikâyet, içerik
  kaldırma ve kullanıcı engelleme araçları zorunlu olur.

### Sadece kişisel kullanım

Uygulama Xcode ile kişinin kendi iPhone'una yüklenirse App Store incelemesine girmez.
Ücretsiz Apple hesabıyla kurulum 7 günde bir yenilenmelidir; yıllık ücretli geliştirici
hesabıyla bir yıl geçerlidir. YouTube Kullanım Şartları yine geçerlidir.

## 5. Önerilen ilk adımlar

Güncel ilk adım: `SpeechTranscriber` ile İngilizce + ducking dinleme testi (S0.1, S0.7;
bkz. [yol haritası](ios-swift-mimari.md#12-yol-haritası)).

1. **Deneme uygulaması:** SpeechAnalyzer bir videodan Türkçe replikleri zaman
   damgalarıyla çıkarabiliyor mu? (Türkçe desteği + zaman doğruluğu.)
2. Bu tutarsa: video seçme (Fotoğraflar/Dosyalar) → replik düzenleme → kayıt →
   AVFoundation montajı.
3. Ses ayırma için Demucs'un Core AI / Core ML'e çevrilmesi ve iPhone 17'de hız ölçümü.
4. İsteğe bağlı: YouTube gömülü oynatıcıyla indirmesiz dublaj modu.

## Kaynaklar

- [SpeechAnalyzer ile konuşmadan yazıya (levelup)](https://levelup.gitconnected.com/bring-advanced-speech-to-text-to-your-app-with-speechanalyzer-6ed25a84586c)
- [Apple SpeechAnalyzer ile Whisper karşılaştırması 2026](https://rohitraj.tech/en/notes/apple-speechanalyzer-vs-whisper-on-device-stt-2026)
- [Align: SpeechAnalyzer kelime zamanı düzeltme](https://huggingface.co/desert-ant-labs/align)
- [Apple forum: iOS 27'de diarization?](https://developer.apple.com/forums/thread/829621)
- [WWDC25 Oturum 251: Audio Mix / ses kaydı](https://developer.apple.com/videos/play/wwdc2025/251/)
- [WWDC26 Oturum 325: Core AI](https://developer.apple.com/videos/play/wwdc2026/325)
- [MacRumors: 2026 Platforms State of the Union](https://www.macrumors.com/2026/06/09/apple-outlines-major-ai-and-developer-tool-updates/)
- [App Store İnceleme Kuralları](https://developer.apple.com/app-store/review/guidelines/)
- Cihazda ses ayıran örnek uygulamalar: [SongSplit AI](https://apps.apple.com/app/songsplit-ai/id6757964697),
  [VSep](https://apps.apple.com/us/app/vsep/id6759715582),
  [Stem Splitter](https://apps.apple.com/us/app/-/id6767773635)
