# HEDEF: Alpemix'in özellik listesini eşitle (satılabilir v1)

## Bağlam

Bugün (20.10.2026) bir denetim yapıldı: **PLAN.md'deki her madde kodda arandı.**
Sonuç: **12 özellik sadece planda yazılı, kodu yok.** 3 özellik yarım (veri var,
arayüz yok). Bu, "plan yazılı" ile "yapılmış" arasındaki fark — ve bugüne kadar
kimse ölçmemişti.

Denetim sonucu (siteye işlendi, `bilgi.html` → 8 · Yapılmayanlar):

| Özellik | Plan | Durum |
|---|---|---|
| Müşteriler rehberi | 5e | ✅ ebc2aac'ta yaptın, bitirmediysen tamamla |
| Siyah ekran modu | 5 | ❌ lafta |
| Otomatik güncelleme | 6 | ❌ lafta |
| Oturum kaydı | 6 | ❌ lafta |
| Canlı destek widget | 6 | ❌ lafta |
| Bayi markası (CMX/CM) | 6 | ❌ lafta |
| Çoklu izleyici | 6 | ⚠️ altyapı var (MaxViewSessions=4), arayüz yok |
| Cihaz envanteri | 6 | ⚠️ veri var (os, agent_version, last_seen_at), ekran yok |
| Raporlama | 6 | ⚠️ süre/byte/fps/yol kaydediliyor, rapor ekranı yok |
| Webhook (ERP/PSA) | 7 | ❌ lafta |
| Cihaz sağlığı (disk/RAM/CPU) | 7 | ❌ lafta |
| Sesli konuşma | 7 | ❌ lafta |
| Wake-on-LAN | 7 | ❌ lafta |
| Duyarlı izleme (K-15) | — | ❌ lafta |
| Abonelik / faturalama | — | ❌ lafta |
| Linux ajanı | 8 | ❌ lafta (8. adım, mobilden sonra) |

## HEDEF

**Alpemix'in özellik listesini eşitle.** Bileşen bazında değil, **müşteri
perspektifinden**: "Alpemix'te olan her şey bizde de olmalı, üstüne 4 farkımız
eklenmiş olmalı."

Bizim dört farkımız (bunlar KORUNACAK, hiçbir şekilde geri alınmayacak):
1. Teknisyen hiçbir şey kurmuyor
2. Veri izolasyonu veritabanı seviyesinde (RLS)
3. Silinemez denetim kaydı (hash zinciri)
4. Cihaz parolası sunucuya hiç gitmiyor

## ÇALIŞMA KURALLARI — yeni ve zorunlu

### 1. Her adım sonunda "yapılmayanlar" raporu ZORUNLU

Her adımın sonunda bana şu tabloyu ver — **kodda olmayan her plan maddesiyle**:

```
| Özellik | Plan adımı | Kod durumu (var / altyapı var / yok) | Not |
```

Bu olmadan adım tamamlanmış sayılmaz. Ben bunu siteye işliyorum.

### 2. Plan tablosu tek kaynak

`PLAN.md`'deki adım tablosu **"beklemede" satırları için de** güncellensin.
Yani bir özellik "yapıldı"ysa plan tablosunda da öyle yazsın. Plan tablosu
gerçeği yansıtmazsa raporun değeri kalmaz.

### 3. Kapsam dışı bırakma, gerekçe yaz

Bir özelliği "yapmıyorum" dersen **gerekçe + karar dosyasına yaz** (K-xx).
"Zor" demek gerekçe değil. "Kullanıcı kararı gerekiyor" diyorsan
`docs/ACIK-KONULAR.md`'ye yaz, atla.

### 4. Testler gerçekten koşsun

Bugüne kadar iki kez "testler geçti" dedik, aslında **atlanan** testler
geçmişti (SendInput hatasında Skip). E2e'de **atlanan** test varsa bunu
ayrıca belirt. "15 geçti, 2 atlandı" gibi.

### 5. Sıra

Önce **eksik sayısı azalan** ve **müşteri yoluna en yakın** olanlar:

```
1. K-30'yu tamamla (yarım kaldı) + bitir, test et        ← devam ediyorsun
2. Siyah ekran modu (5. adım)          — en çok öne çıkan eksik
3. Otomatik güncelleme (6. adım)        — kullanıcı "güncelle" butonu görmemeli
4. 3 yarım özelliği tamamla (6. adım): çoklu izleyici, cihaz envanteri, raporlama
5. Oturum kaydı (6. adım)
6. Canlı destek widget (6. adım)
7. Fiyat/plan arayüzü (6. adım) — KARAR KULLANICIDA, docs/ACIK-KONULAR.md'ye yaz
```

6 ve 7 dışındakiler kod işidir, para gerektirmez.

**8. adım (Linux ajanı) ve 9–10 (mobil) sonra.** Kullanıcı sırayı belirledi:
Windows → Linux → mobil izleme → mobil kontrol.

## ÖZELLİK DETAYLARI (Alpemix'in davranışına göre)

### Siyah ekran modu (5. adım)
Alpemix: "uzaktan bağlandığınız bilgisayarın monitörünü uzaktan tamamen
kapatarak o bilgisayarın başındaki kişinin ne işlem yaptığınızı görmesini
engelleyebilirsiniz. Bunu yapabilmeniz için gönderdiğiniz teklifi karşıdaki
kişinin kabul etmesi gerekir. Karşı bilgisayarda servis uygulaması kurulu
ise teklife gerek kalmadan direk siyah ekran moduna geçebilirsiniz."

Bize uyan kısım: **müşteri onayı zaten var** (onay penceresi). Yani
teklif/kabul zaten mevcut. Yapılacak: onay sonrası bir "siyah ekran" modu
seçeneği ve ajanda ekran akışını durdurma (görüntü gönderme, ama girdi
çalışmaya devam etsin). Dikkat: müşteri kendi ekranında bir onay penceresi
görmeye devam etmeli mi? Alpemix'te ekran tamamen kapanıyor — bizde onay
penceresi de kapanırsa müşteri ne onaylayacaktı? Kararı `KARARLAR.md`'ye yaz.

### Otomatik güncelleme (6. adım)
Alpemix: "Alpemix'e yeni özellikler eklendiğinde birkaç saniye içinde
otomatik olarak kendini yeniler... Ana kullanıcı adınızla giriş yapıp
listelenen menü seçeneğini kullanarak uzak bilgisayarlarınızda kurulu olan
alpemix servis uygulamalarının kolayca güncellenmesini sağlayabilirsiniz."

Bizim durum: protokolde "sürüm alanı" var, imzalı manifest için iskelet
var, **aktif değil**. Gerekenler: imzalı manifest sunucusu, ajanın sürüm
kontrolü, indirme + doğrulama + geri alma, sessiz/kullanıcı onaylı kurulum.
Kod imzası sertifikası kullanıcı kararı (6. adım) — **ama imzasız da
çalışabilir olmalı** (geliştirme için).

### 3 yarım özellik
- **Çoklu izleyici:** ajan tarafı hazır (`MaxViewSessions = 4`). Eksik: konsol
  arayüzü + kaç izleyici bağlı + "izleme" rolüyle bağlanma akışı.
- **Cihaz envanteri:** `devices.os`, `devices.agent_version`,
  `devices.last_seen_at` doluyor. Eksik: konsolda liste + sürüm karşılaştırma
  ("bu cihaz güncel değil").
- **Raporlama:** `support_sessions` içinde süre/byte/fps/candidate_type var.
  Eksik: rapor API'si + arayüz (tarih aralığı, teknisyen, cihaz, P2P/relay
  oranı). **Relay oranı raporu fiyatlamanın temeli** — yüksek öncelik.

## GÜVENLİK

Her adımda güvenlik denetimi. Yüksek/orta bulguyu bırakma.
Özellikle: uzaktan güncelleme (imza doğrulama zorunlu olmalı), oturum kaydı
(kim erişebilir, şifreli mi, saklama süresi), siyah ekran (kilit ekranı
kaydı, uzaktan gönderilen tuşlar kaydediliyor mu).

## KALİTE KAPISI

`CGO_ENABLED=0 go build` · `go vet` · `golangci-lint` · `go test` · e2e ·
test matrisi · güvenlik denetimi.

**E2e'de atlanan testleri ayrıca bildir.**

## RAPORLAMA

Her adım sonunda bana:
1. Ne değişti (kısa)
2. **Yapılmayanlar tablosu** (yukarıdaki formatta, güncel)
3. Test sonuçları + **atlanan testler**
4. Kullanıcı kararı gerekenler (`docs/ACIK-KONULAR.md`'ye eklendi mi?)
5. Push onayı için commit listesi

Push yapma. Ben yaparım, CI'yı kontrol ederim.
