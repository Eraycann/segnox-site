# Plan değişikliği isteği — mobil ajan (A + B)

Kullanıcı kararı: **Mobil ajan plana alınsın.** Öncelik sırası kesin.

## Sıra

1. **Windows ajanı tamamlanır** — gözetimsiz erişim (5a/5b/5c) + H.264 (5d).
2. **Linux ajanı** (X11) — ekran yakalama + tuş gönderimi. Wayland yok (K-şimdilik-yok).
3. **A) Mobil ajan — sadece izleme** (Android + iOS).
4. **B) Mobil ajan — tam kontrol** (sadece Android, AccessibilityService).

1 ve 2 bitmeden 3 ve 4'e başlama. 3 ve 4 aynı ajan tabanını kullanacak
(sunucu/WebRTC/TURN/roller/cihaz parolası zaten hazır); sadece ekran yakalama
ve girdi katmanı değişecek. Bu yüzden geciktirmek bedeli düşük.

## A) İzleme — neden kolay ve neden güvenli

- Android: `MediaProjection` yayını. Kullanıcı bir kez dokunur.
- iOS: `ReplayKit` yayını. Kullanıcı her oturumda bir kez dokunur.
- İkisi de **yasal** ve mağazaya konabilir.
- Kullanıcı onayı zorunlu olması bizim güvenlik anlatımızla **örtüşüyor**
  (mevcut onay penceresi zaten var).

## B) Kontrol — neden sadece Android

| | Ekran görüntü | Tıklama/tuş |
|---|---|---|
| Android | ✅ | ✅ `AccessibilityService` |
| iOS | ⚠️ kullanıcı her seferinde başlatır | ❌ **imkânsız** (jailbreak dışında yok) |

Rakibin durumu (Alpemix, doğrulanmış): Google Play sürümü **sadece izleme**
yapabiliyor. Tam kontrol için site'dan APK indiriliyor, kullanıcı Play Protect'i
geçici kapatıyor, "Kısıtlı ayarlara izin ver" diyor, sonra Erişilebilirlik
iznini veriyor. **Rakibin de mağaza sürümü tam kontrol yapamıyor.**

Bilinen riskler B için:
- Android 13+ sideload edilen APK'ların erişilebilirlik iznini otomatik kapatıyor;
  "Kısıtlı ayarlara izin ver" gerekiyor. Bazı Samsung modellerinde bu menü hiç görünmüyor.
- Google Play yolu: erişilebilirlik API'si için **beyan formu + onay** gerekli.
  Engelli erişimi dışı amaçla kullanım ayrıca "belirgin onay ekranı" şart.
- Erişilebilirlik API'si kötüye kullanılıyor (banka trojanları). Google sıkılaştıkça
  bizim onay yenileme riskimiz artar. **Bu maliyeti karar dosyasına yaz.**

## Yeni adım numaraları (PLAN.md'ye eklenecek)

- `5e` — Mobil ajan: izleme (Android + iOS)
- `5f` — Mobil ajan: tam kontrol (Android)

## Aynı pakette çözülecek iki iş (Alpemix karşılaştırmasından çıktı)

### 1. "Müşteri" kavramı yok

Şu an: `tenants → users → devices`. KOBİ saha teknisyeni günde 8-10 farklı
müşteriye yardım ediyor; "bugün kime yardım ettim" listesini tutacak bir yer yok.
Rakipte adres defteri var ve müşteri **kurulumdan önce** kaydedilebiliyor.

Öneri: `customers` tablosu (tenant'a bağlı, ad/kişi/telefon/e-posta/not),
`devices` ile ilişkilendirilebilir ama cihaz olmadan da var olabilir.
`enrollment_tokens` zaten var — kurulum bağlantısı bu tablo üzerinden üretilebilir.
**Geriye uyumlu migration.** Bu iş A'dan **önce** yapılır; A'nın cihaz listesi
boş görünmesin.

### 2. İstek tipi ayrımı yok

`support_requests` tek tip. "Yardım et" ile "sadece izle" ayrımı yok; rol oturuma
bağlanırken belirleniyor. Müşteri isteği açarken niyetini belirtemiyor.

Öneri: `support_requests.kind` sütunu (`assist` | `watch`), geriye uyumlu.
`watch` isteklerinde rol otomatik `view` olur, kontrol istenemez.

## Not — ajan dili

Android için Kotlin/Java yazmak **gerekmiyor**. `golang.org/x/mobile`
(gomobile) ile saf Go → Android derlenebilir, cgo gerekmez. Bu, CLAUDE.md'deki
"cgo yok" kuralını bozmaz. Araştır ve karar dosyasına yaz.

## Bu iş adımı engellemesin

5a–5d (Windows), Linux ajanı ve 6. adım (gerçek sunucu) mobil işi engellemez.
Sırayı bozma, kendi planında devam et.