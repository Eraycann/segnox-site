# Segnox — Claude Code'a verilecek metin (21.10.2026)

> Bu dosyayı **elle Claude Code'a yapıştıracaksın**. Push yok — push'u asistan yapar.
> Bu turda istenen: **3 gerçek makine hatasının düzeltilmesi** (ürün kodu = sen).

---

## 1 · Nerede kaldık

- 6a–6g **bitti** (otomatik güncelleme, çoklu izleyici, envanter, raporlama,
  oturum kaydı, canlı destek düğmesi, bayi markası). CI **4/4 yeşil**,
  e2e 36 geçti / 3 atlandı / 0 kaldı.
- **Bugün (21.10) Windows 11 VM'de gerçek makine testleri yapıldı** (asistan).
  Servis kipi (K-26) **geçti**: kurulum çıkış kodu 0, `device enrolled`,
  servis `LocalSystem` + AUTO_START, helper SYSTEM, `ProgramData\Segnox` ACL
  yalnız SYSTEM+Administrators, ajan "registered with signaling server" ve
  host'ta cihaz **çevrimiçi** göründü.
- **Ama üç gerçek hata çıktı.** Aşağıda. Hepsi **senin** alanında: ürün kodu.

## 2 · Hata 1 — Onay penceresi (ui-host) servis kipinde anında ölüyor
**EN KRİTİK.** Müşteri onayı olmadan bağlantı kurulamıyor; ürünün kalbi bu.

Konuk ajan logu (Windows 11, servis kipi, SYSTEM):
```
"msg":"ui-host started","pid":9504
"msg":"ui-host attached"
"msg":"ui-host connection lost, restarting","err":"ipc: connection closed","backoff":1000000000
"msg":"ui-host started","pid":5340
"msg":"ui-host attached"
"msg":"ui-host connection lost, restarting","err":"ipc: connection closed","backoff":2000000000
"msg":"ui-host started","pid":596
"msg":"ui-host attached"
"msg":"ui-host connection lost, restarting","err":"ipc: connection closed","backoff":4000000000
```
Yardımcı SYSTEM olarak çalışıyor, oturum 1 bulundu ("helper started","session":1,
"ui_host":true) → ui-host **başlıyor, bağlanıyor, bağlantı hemen kopuyor.**
Ajan süreci SYSTEM olarak kalıyor, "ui-host yok ya da SYSTEM" uyarısı verildi.

**Baktığın yerler:** `internal/agent/ipc` (named pipe, elde tutma), `internal/agent/ui`
(webview/pencere), `cmd/segnox-agent` içindeki **ui-host** komutu ve helper'ın
kullanıcı oturumunda (session 1) süreç başlatma yolu, `internal/agent/session`.
**E2E'de görünmüyor** (orada ui-host yok, her şey headless).

## 3 · Hata 2 — `SEGNOX_PUBLIC_URL` uyuşmazlığı TÜM cihazları "revoked" gibi reddediyor

Cihaz imzası **sunucu host'unu** içeriyor:
- Ajan imzalıyor: `internal/agent/device/device.go:83` →
  `proto.DeviceAuthMessage(nonce, deviceID, host)` — `host` = **ajanın kendi
  /SERVER= URL'sinin hostname'i** (`u.Hostname()`).
- Sunucu doğruluyor: `internal/server/signal/deviceauth.go:154` →
  `ed25519.Verify(a.pub, proto.DeviceAuthMessage(nonce, id, c.hub.publicHost), sig)`
  — `publicHost` = **`SEGNOX_PUBLIC_URL`'ın hostname'i**
  (`cmd/segnox-server/config.go:323`).

İkisi farklıysa imza tutmuyor → sunucu `unauthorized` döner → ajan şunu yazıyor:
```
"msg":"server refused the device identity; it may have been revoked"
```
**"revoked" yalanı.** Cihaz iptal edilmemiş, sadece host eşleşmiyor. Bizim
testte tam olarak bu oldu: `SEGNOX_PUBLIC_URL=http://127.0.0.1:8090` iken ajan
`https://192.168.79.1:8080` kullanıyordu → cihaz hiç bağlanamadı.

**İstenenler:**
1. **Ajanın hata mesajı yanlış olmasın**: "sunucu kimliğimizi reddetti; sunucu
   adresi ile sunucunun public host'u eşleşmiyor olabilir" gibi gerçekçi bir
   mesaj (K-xx kararına gerekebilir, ama "revoked" demek yanlış).
2. **Sunucu tarafında teşhis**: `SEGNOX_PUBLIC_URL`'ın hostname'i ile cihazın
   imzaladığı hostname farklıysa logda net bir satır olsun.
3. **`deploy/.env.example` ve `docs/OPERASYON.md`**: "SEGNOX_PUBLIC_URL'ın
   hostname'i, ajanlara verilen /SERVER= adresinin hostname'i ile aynı olmalı
   (port farklı olabilir)" kuralı yazılsın — şu an `.env.example`'da
   PUBLIC_URL satırı yok.

## 4 · Hata 3 — Ajan, loopback dışındaki düz HTTP sunucuyu reddediyor

`internal/agent/device/device.go` → `BaseURL()`:
```
case "http": if !isLoopback(host) { return "", errors.New("device: https required for a non-loopback server") }
```
Kurulum **çıkış kodu 2** ile düşüyor ("usage error"). Bu K-21'in bilinçli
kuralı (genel adres https zorunlu) — **ama ürünün "kendi sunucusuna kurulum"
özelliği bu yüzden düz HTTP'de çalışamıyor.** Bizim testte de aynı sebeple
TLS proxy + konukta güvenilir kök kurmak zorunda kaldık.

**Karar gerekiyor (senin + kullanıcının):**
(a) Kural aynen kalır → self-host müşterisi TLS kurmak zorunda; **belgelenmeli**
    (kendi CA'sını ajana yükleyebilmek de gerekiyor).
(b) Açık bir opt-in bayrağı: `/SERVER=http://...` + `/INSECURE` (veya
    `SEGNOX_ALLOW_INSECURE=1`) → yalnız gizli IP'lerde, **gürültülü logla**.
    (Bu yeni bir güvenlik yüzeyi; K-xx gerekir.)
Benim tercihim: **(a) + kendi CA yükleme desteği** (kendi sunucunu kuran
müşteri zaten kendi CA'sını kullanacak). Kararı kullanıcıya sor.

## 5 · Bundan sonra

1. **Yukarıdaki 3 hatayı düzelt** (yeni özellik değil, düzeltme). Her biri için:
   kök neden, düzeltme, test (e2e'ye eklenebilecek bir test varsa ekle).
2. **"Yazıldı" → "çalışıyor" ayrımını güncelle**: PLAN.md ve 6e/6f raporlarında
   "gerçek makinede doğrulandı" işaretle (servis kipi artık doğrulandı).
3. **7. adımı (ses, cihaz sağlığı, webhook, WoL) acele etme** — satışa
   katkısı yok; önce fiyat (KULLANICI KARARI) + dağıtım (VPS/alan adı) +
   kod imzası + KVKK metni. Kullanıcı, satışa odaklanmak istiyor.
4. 6h için `docs/ACIK-KONULAR.md #8`'deki altı soruyu kullanıcı cevaplayacak;
   sen sadece "hazır" de.

## 6 · Kurallar (değişmedi)

- **Push yok.** Commit'le, asistan push + CI yapar.
- Her adım sonunda: **ne değişti** · **yapılmayanlar tablosu**
  (`| Özellik | Plan adımı | Kod durumu | Not |`) · **test sonuçları + atlanan
  testlerin adları** · **ACIK-KONULAR** · **commit sayısı**.
- **"Atlanan" testleri "geçti" sayma** (isimleriyle yaz).
- **"Tamam" deme, "bitti" de** — kod bitti, gerçek makine kanıtı bekliyor.
- **"Flaky" deme, kök nedeni bul.**
- `docs/DEVAM.md` ≤ ~40 satır.
- Kod = sen, site = asistan. Aynı dosyaya dokunma.

## 7 · Not (asistanın işi, senin değil)

Windows 11 VM test koşumları `.tools/vm-test.ps1` ile otomatik:
`.\vm-test.ps1 -Senaryo hazirlik|servis|siyah|izleyici|guncelleme|devam`.
E2e'de görünmeyen hataları bulmak için kullanılıyor — **Hata 1 ve 2 düzeldikten
sonra asistan bu senaryoları yeniden koşacak.**
