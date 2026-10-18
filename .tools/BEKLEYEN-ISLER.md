# Bekleyen işler — tek teslim (18.10.2026)

Öncelik sırası. **1 ve 2 acil**, 3 ve 4 kayıt altına alınacak, hemen yapılmayacak.

---

## 1 · ACİL — CI'da iki kırık test

`05682ec` push edildi, run `39146717563` → **failure**.

| İş | Hata |
|---|---|
| `linux (race)` | `TestResumeSameBootRefused/same_boot` → `power_test.go:401: OnStart not called` |
| `windows` | `TestNoFileTransferClosesFileChannel` → `nofile_test.go:22: timeout waiting for agent.info` |

İkisi de **5c (yeniden başlat + devam) ve servis kipindeki denetim
düzeltmelerinin kendi testleri.** Yani yeni kodun testleri.

`TestResumeSameBootRefused` adı "aynı açılışta devam reddedilir" diyor; `OnStart`
çağrılmamış. Bu gerçek bir eksik olabilir (servis kipinde ajanın başlatma geri
çağrısı çalışmıyor) ya da test düzeneği. **Varsayımda bulunma, ikna edici sebep
göstermeden "flaky" deme.** `-race` ve `-count` ile tekrarla, kök nedeni bul.

`TestNoFileTransferClosesFileChannel` "servis kipinde dosya aktarımı kapalı
olmalı" diyor; `agent.info` 15 sn içinde gelmedi.

Kırmızı CI bırakma. Üstelik iki dalga üst üste aynı kalıpta test kırıldı:
sahiplik testleri de "yanlış şey kanıtlıyordu". Bu testlere de aynı gözle bak.

---

## 2 · ACİL — `SEGNOX_ORIGINS` API'ye uygulanmıyor

```
main.go:142   OriginPatterns: [publicOrigin, cfg.origins...]   → sadece viewer WebSocket
api.go:129    origin: normOrigin(cfg.PublicURL)                → API sameOrigin, origins'ı yok sayıyor
```

Belirti: sunucu `0.0.0.0:8080`'e bağlı, ikinci cihazdan
`http://192.168.1.26:8080` açılıyor, `healthz` **200** dönüyor, giriş sayfası
yükleniyor, `POST /api/v1/auth/login` **403** dönüyor ("yetkiniz yok").

Doğrulama (kullanıcı tarafında yapıldı):

| İstek | Sonuç |
|---|---|
| `Sec-Fetch-Site: same-origin` başlığıyla | **200** |
| `Sec-Fetch-Site` yok, sadece `Origin` | **403** |
| `Sec-Fetch-Site: cross-site` | **403** |
| `Origin` yanlış port | **403** |

Ağ, güvenlik duvarı, sunucu ve veritabanı sağlam. Tek kapı origin kontrolü.

İstenen:

1. `SEGNOX_ORIGINS` içindeki host'lar **API `sameOrigin` kontrolünde de** kabul
   edilsin. `publicOrigin` ile birlikte izin listesi olsun, `normOrigin` ile
   karşılaştırsın.
2. `maxOrigins` (32) sınırı korunsun.
3. Birim testi: listedeki bir origin ile 200, listede olmayan bir origin ile 403.
   Mevcut `api_test.go` ve `origin_test.go` genişletilsin.
4. Bu "test kolaylığı" değil, **davranış düzeltmesi**: bayrağın adı "extra
   allowed viewer Origin hosts" ama HTTP yüzeyinin tamamını kapsamalı. Geriye
   uyumlu olsun: tek origin'li kurulumlarda davranış değişmesin.

Bunu düzeltmeden **fare/klavye gerçek testi yapılamıyor** — çünkü tek yol ikinci
bir cihaz (telefon/VM) ve hepsi aynı origin hatasına düşüyor. Bilgisayarın
kendisinden bağlanınca tıklamayı yine tarayıcı yakalıyor.

---

## 3 · PLANA AL — Mobil ajan (A ve B)

Araştırma sonucu ve karar aşağıda. **Şimdilik kod yazma.** `PLAN.md`'ye adım
olarak ekle, `KARARLAR.md`'ye karar olarak yaz (K-27/K-28'den sonra bir numara).

### Sıra (kesin, atlanmayacak)

1. Windows ajanı tamamlanır — gözetimsiz erişim + H.264  ← **şu an burada**
2. Linux ajanı (X11)
3. **A) Mobil ajan — sadece izleme** (Android + iOS)
4. **B) Mobil ajan — tam kontrol** (yalnız Android)

1 ve 2 gerçek makinede doğrulanmadan 3 ve 4'e başlama.

### A) İzleme — neden kolay ve neden güvenli

- Android: `MediaProjection` yayını, kullanıcı bir kez dokunur.
- iOS: `ReplayKit` yayını, kullanıcı her oturumda bir kez dokunur.
- İkisi de yasal, mağazaya konabilir.
- Kullanıcı onayı zorunlu olması mevcut onay penceresiyle örtüşüyor.

### B) Kontrol — neden yalnız Android

| | Ekran görüntü | Tıklama/tuş |
|---|---|---|
| Android | ✅ | ✅ `AccessibilityService` |
| iOS | ⚠️ kullanıcı her seferinde başlatır | ❌ **imkânsız** (jailbreak dışında) |

**Rakibin durumu (Alpemix, kendi sitesinden doğrulandı):** Google Play sürümü
telefona bağlandığında **sadece izleme** yapabiliyor. Tam kontrol için site'dan
`AlpemixPro.apk` elle indiriliyor, kullanıcı Play Protect'i geçici kapatıyor,
"Ayarlar > Uygulamalar > Alpemix > ⋮ > Kısıtlı ayarlara izin ver" diyor,
ardından **Erişilebilirlik** iznini veriyor. **Rakip de mağaza sürümüyle tam
kontrol yapamıyor.**

Bilinen riskler (karar dosyasına yaz):

- Android 13+ sideload edilen APK'ların erişilebilirlik iznini otomatik kapatıyor.
- Bazı Samsung modellerinde "Kısıtlı ayarlara izin ver" menüsü hiç görünmüyor —
  rakibin bu yöntemi her telefonda çalışmıyor.
- Google Play yolu: erişilebilirlik API'si için beyan formu + onay + belirgin
  onay ekranı gerekiyor. Süreç haftalar sürer.
- Erişilebilirlik API'si kötüye kullanılıyor (banka trojanları); Google
  sıkılaştıkça bizim onay yenileme riskimiz artar.

### DİL NOTU

Android için Kotlin/Java yazmak **gerekmiyor**. `golang.org/x/mobile`
(gomobile) ile saf Go → Android derlenebilir, cgo gerekmez — CLAUDE.md'deki
"cgo yok" kuralı bozulmaz. Araştır ve karar dosyasına yaz.

### Mağaza hesabı maliyeti (bilgi)

Google Play **$25 bir kez**, Apple **$99/yıl**. Hesaplar müşteri bulunduğunda
açılacak.

---

## 4 · PLANA AL — Alpemix karşılaştırmasından çıkan iki eşik

Kullanıcı Alpemix'in Play Store ilanını inceledi. Bizim kod taranarak
karşılaştırıldı:

| Alpemix ilanındaki | Bizim durumumuz |
|---|---|
| Yetkiler | ✅ 4 rol: owner / admin / technician / viewer |
| Çalışma arkadaşları | ✅ `users` + e-posta daveti |
| **Müşteriler** | ❌ **kavram yok** |
| Destek teklifi gönder | ✅ `support_requests` |
| **İzleme teklifi gönder** | ❌ **tek tip, ayrım yok** |
| Sürekli erişim parolası | ✅ cihaz parolası |

### 4a — `customers` tablosu

Şu an: `tenants → users → devices`. KOBİ saha teknisyeni günde 8–10 farklı
müşteriye yardım ediyor; "bugün kime yardım ettim" listesini tutacak yer yok.
Rakipte adres defteri var ve müşteri **kurulumdan önce** kaydedilebiliyor.

Öneri: `customers` tablosu (tenant'a bağlı; ad, kişi, telefon, e-posta, not),
`devices` ile ilişkilendirilebilir ama **cihaz olmadan da var olabilir**.
`enrollment_tokens` zaten var — kurulum bağlantısı bu tablodan üretilebilir.
Geriye uyumlu migration, RLS zorunlu, `store.InTenantTx` üzerinden.

**Mobil işinden önce yapılır** — yoksa A'nın cihaz listesi boş görünür.

### 4b — `support_requests.kind`

`support_requests` tek tip. "Yardım et" ile "sadece izle" ayrımı yok; rol
oturuma bağlanırken belirleniyor. Müşteri isteği açarken niyetini belirtemiyor.

Öneri: `kind` sütunu (`assist` | `watch`), geriye uyumlu (mevcut satırlar
`assist`). `watch` isteklerinde rol otomatik `view` olur, kontrol istenemez.

---

## Çalışma düzeni (CLAUDE.md'ye zaten yazılı, hatırlatma)

- Gerçek makine / VM / farklı ağ denemesi sende yapılamaz →
  `docs/ACIK-KONULAR.md`'ye ekle, atla, bağımsız işlerle devam et.
- Servis kipini **kullanıma hazır ilan etme**. Gerçek ortamda hiç denenmedi.
- Her adımda güvenlik denetimi; orta/yüksek bulguyu bırakma.
- Kalite kapısı: `CGO_ENABLED=0 go build` · `go vet` · `golangci-lint` ·
  `go test` · e2e · test matrisi · güvenlik denetimi.
- **Push yapma.**

## Sıra özeti

1 → CI'yi yeşile getir (2 kırık test, kök nedenle)
2 → `SEGNOX_ORIGINS` API'ye (birim testiyle)
3 → Mobil planı + K-27/K-28 sonrası karara yaz, kod yazma
4 → `customers` + `support_requests.kind` — **5. adım paketine ekle**, mobil işini engellemesin