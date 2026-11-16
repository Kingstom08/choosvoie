# ChoosVoie iOS

## Yapı

| Dizin | Açıklama |
|-------|----------|
| `ChoosVoieCore/` | Platformdan bağımsız saf Swift paketi (`swift test` ile test edilir). |
| `ChoosVoie/` | SwiftUI iOS uygulaması (hedef iOS 26, bundle id `com.kingstom08.choosvoie`). |
| `project.yml` | XcodeGen proje tanımı. |

## Gereksinimler

- Xcode 26+
- XcodeGen: `brew install xcodegen`

## Projeyi üretme ve açma

```sh
cd ios && xcodegen generate && open ChoosVoie.xcodeproj
```

`.xcodeproj` git tarafından yok sayılır. `project.yml` değiştiğinde veya yeni dosya eklendiğinde yeniden üretin.

## Paket testleri

```sh
cd ios/ChoosVoieCore && swift test
```

## Fiziksel iPhone'da çalıştırma

1. iPhone'da Developer Mode'u açın (Ayarlar > Gizlilik ve Güvenlik > Developer Mode).
2. Uygulamayı Xcode'dan cihaza yükleyin.
3. Ayarlar > Genel > VPN ve Cihaz Yönetimi altında geliştirici profiline güvenin.
4. Ücretsiz Apple ID ile imzalanan uygulamalar 7 gün sonra geçersiz olur; yeniden yükleyin.

## Belgeler

- [docs/ios-swift-mimari.md](../docs/ios-swift-mimari.md)
- [ChoosVoieCore/SPEC.md](ChoosVoieCore/SPEC.md)
