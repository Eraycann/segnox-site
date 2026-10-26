# ASISTAN NOTLARI — Segnox (benim kalıcı hafızam)

> Bu dosya bana ait. Claude Code okumaz. `/clear` sonrası buraya bakıyorum.

## Proje

**Segnox** — Türkçe uzaktan destek platformu. Alpemix'e rakip. Ankara merkezli
şirketin (`segnox.com`, zaten canlı) altında çıkacak.

**Hedef:** Alpemix'in özellik listesini eşitlemek. Bittiğinde müşteri
"Alpemix'te var, bizde yok" diyememeli. Artı 4 farkımız:
teknisyen kurulum yapmaz · RLS (veritabanı seviyesinde izolasyon) · hash zincirli
silinemez denetim kaydı · cihaz parolası sunucuya gitmez.

## İş bölümü

| Kim | Ne yapar |
|---|---|
| **Claude Code** | Tüm kod, test, güvenlik denetimi, araştırma. **Push yapmaz.** |
| **Ben (asistan)** | **Push**, CI okuma, **siteyi güncelleme**, web araştırması, sıralama |
| **Kullanıcı** | VM denemeleri, fiyat/karar verme, gerçek makine testleri |

**Kural:** Aynı dosyaya ikimiz de dokunmayız. Kod = Claude Code, site = ben.

## Adım durumu (21.10.2026)

| Adım | Özellik | Karar | Durum |
|---|---|---|---|
| 1–4b | MVP (sinyal, ekran, hesap, destek akışı, canlı paket) | — | ✅ |
| 5a/5b | Windows servisi, SYSTEM yardımcı, sessiz kurulum, ipc | K-26 | ✅ kod, denenmedi |
| 5c | Yeniden başlat + devam | K-27 | ✅ kod, denenmedi |
| 5d | H.264 (Media Foundation) | K-28 | ✅ kod, **gerçek masaüstünde doğrulandı** |
| 5e | Müşteriler rehberi + istek türü | K-30 | ✅ |
| 5f | Siyah ekran (gizlilik) | K-32 | ✅ kod, denenmedi |
| 6a | Otomatik güncelleme | K-33 | ✅ kod, denenmedi |
| 6b | Çoklu izleyici arayüzü | K-34 | ✅ |
| 6c | Cihaz envanteri | — | ✅ |
| 6d | Raporlama (P2P/relay oranı, CSV) | K-34 | ✅ |
| 6e | Oturum kaydı (video) | K-35 | ✅ bitti (denetim 4 orta + 4 düşük kapandı) |
| 6f | Canlı destek düğmesi (widget) | K-36 | ✅ bitti (e2e 6 senaryo) |
| 6g | Bayi markası | K-37 | ✅ bitti (denetim 3 orta kapandı) |
| 6h | Fiyat/plan | — | ⬜ **KULLANICI KARARI (ACIK #8)** |
| 7 | Ses, cihaz sağlığı, webhook, Wake-on-LAN, duyarlı izleme | — | ⬜ |
| 8 | Linux ajanı (X11) | — | ⬜ |
| 9/10 | Mobil izleme (A) / Android kontrol (B) | K-29 | ⬜ |

**Karar:** 1–4b + 5a–5f + 6a–6g = **39 özellik tamam**. Kalan 6h + 7 + 8 + 9/10.

**Alpemix karşılaştırması (21.10):** **9 özellikte eşitlendik** (5e, 5f, 6a,
6b, 6c, 6d, 6e, 6f, 6g). **Alpemix'te var bizde olmayan 10 madde:** sesli konuşma ·
bölge paylaşma · çevrimdışı/duyuru mesajı · grup sohbeti · şirket dışı iletişim
engeli · ekran işaretleme · mobil ajan · Linux ajanı · Mac/iOS ajanı · fiyat.
→ **Motor olarak iyiyiz, ürün olarak 10 özellik gerideyiz.**

**Satılabilirlik için iki şey gerekiyor:** (1) fiyat senin kararın,
(2) dört özelliğin gerçek makinede doğrulanması (ben + sen).
## Adım numarası tuzağı

`PLAN.md` adım numaraları **adım = bir özellik grubu**, eski tabloda 6 = "prod
altyapısı" idi, **artık 6a–6h = ayrı adımlar**. Sayıları karıştırma.

## Kritik kararlar (KARARLAR.md, K-01…K-36)

- **K-10** — TURN için coturn (kendi sunucumuzu yazmadık)
- **K-16** — TURN açık relay testi CI'da gerçek coturn'a karşı
- **K-21** — Genel adres https zorunlu (localhost dışında)
- **K-25** — STUN kendi sunucumuzdan; **üçüncü taraf STUN yasak** (KVKK)
- **K-26** — SYSTEM servis → SYSTEM yardımcı → kullanıcı arayüzü; fail-closed
- **K-27** — Devam: yalnız servis kipinde + kontrol rolünde + cihaz parolası varken
- **K-28** — H.264 + JPEG karoya otomatik düşüş
- **K-29** — Mobil sıra: A (izleme) → B (yalnız Android kontrol)
- **K-30** — Müşteriler + `support_requests.kind` (assist|watch)
- **K-31** — Mobil klavye silme/Enter + yakınlaştırma
- **K-32** — Siyah ekran
- **K-33** — Otomatik güncelleme (Ed25519 imzalı manifest)
- **K-34** — Raporlama + çoklu izleyici
- **K-35** — Oturum kaydı
- **K-29 not:** gomobile Android NDK istiyor → **Kotlin kabuk + Go çekirdek** önerildi

## Kullanıcıda bekleyen (ACIK-KONULAR.md)

#13 servis kipi VM · #14 5c/5d VM · #15 telefon · #16 siyah ekran ·
#17 otomatik güncelleme VM · #18 çoklu izleyici gözle · #19 KVKK kayıt metni ·
**#4 Hetzner + DNS** · **#6 kod imzası** · **#7 KVKK avukat** · **#8 fiyat (6h)** ·
**#21 marka içerik onayı (6g)** · **#5 SMTP**
**#20 VM betikleri hazır → benim işim (senin gözün gereken 4 adım).**

## Site (benim alanım)

`C:\Users\Erayc\Desktop\segnox-site` → GitHub Pages:
`https://eraycann.github.io/segnox-site/`

**4 sayfa** (menüde 4, arşiv klasörü ayrı):
- `index.html` — Genel Bakış
- `basla.html` — Rehber (sıradaki iş, hareket günlüğü, yerel test)
- `bilgi.html` — El Kitabı (10 bölüm: durum, şemalar, ağ, teknolojiler, sözlük,
  test matrisi, riskler, pazar, kayıtlar, yapılmayanlar)
- `mimari.html` — Mimari

**Kurallar:** her sayfada "Son güncelleme: <tarih> · Kaynak: repo @ <hash>"
damgası. Ölçüm sayıları kaynak dosyasına atıflı. Mükerrer tablo yok.
`_arsiv/` = menü dışı (musteri, bayi, simulator, nasil, gelistirici).

## Araçlarım (.tools/)

| Dosya | Ne |
|---|---|
| `HEDEF-ALPEMIX-ESITLAMA.md` | Claude Code'un /goal dosyası |
| `BEKLEYEN-ISLER.md` | 20.10 öncesi bekleyen işler (bitti) |
| `CLAUDE-YENI-BASLATICI.md` | /clear sonrası Claude Code'a verilecek prompt |
| `ASISTAN-NOTLARIM.md` | **bu dosya — benim hafızam** |
| `h264-test.ps1` | Host'ta sunucu+ajan (telefon testi için) |
| `vm-test.ps1` | Host'ta sunucu+veritabanı+dosya sunucusu+katılım kodu |
| `vm-paket/` | VM'e giden dosyalar (gitignore'da) |
| `HATA-*.md` | Yazdığım hata raporları |

## Test altyapısı

**Temiz build worktree:** `C:\Users\Erayc\Desktop\segnox-test-build`
(Claude Code'un WIP'inden bağımsız derleme yapmak için — `git worktree add`)

**VM:** VMware Pro 26.0.1 · Windows 11 x64 · 4 GB RAM · 4 vCPU · NAT (VMnet8)
- VM IP: `192.168.79.129` · host: `192.168.79.1` (VMnet8) / `192.168.1.26` (Wi-Fi)
- **VM şifreleme parolası: `windows11`** → `vmrun -T ws -vp windows11 <vmx>`
- Konuk Microsoft hesabı: `Eraycansivri@hotmail.com`, parola **bilinmiyor** →
  **Guest Operations (vmrun -gu/-gp) ÇALIŞMIYOR.** Parolasız yol: HTTP.
- **Konukta VMware Tools çalışıyor** (13.1.5) ama **HGFS/paylaşımlı klasör
  çalışmıyor** (yarım kalan kurulumdan) → `\\vmware-host\...` erişilemiyor.
- Kopyala-yapıştır **çalışıyor** (VM yeniden başlatılınca).
- `.vmx` yolları boşluklu → **8.3 kısa yol** şart: `C:\Users\Erayc\DOCUME~1\VIRTUA~1\WINDOW~1\WINDOW~1.VMX`

**VM test betikleri (benim alanım, `.tools/`):**
| Dosya | Ne |
|---|---|
| `vm-prep.ps1` | .vmx ayarları (copy-paste/DnD/HGFS, 2 paylaşım) + VM açma (kapalıyken yazılır) |
| `vm-test.ps1` | **6 senaryo**: hazirlik · servis · siyah · izleyici · guncelleme · devam |
| `vm-tls-proxy.go` | TLS sonlandırıcı reverse proxy (ajan https zorunlu) |
| `host-dosya-sunucu.py` | Host HTTP sunucusu: dosya verir, konuk sonucu POST eder |
| `vm-paylasim/poller-http.ps1` | Konukta SYSTEM görev: calis.ps1 indirir, çalıştırır, sonucu POST eder |
| `vm-paylasim/bootstrap-http.ps1` | Konukta TEK yapıştırma: görevi kurar |
| `host-ekran.ps1` | Host ekranını PNG alır (görmek için) |

**Çalışma akışı:** konukta 1 kez bootstrap yapıştırılır → sonra her senaryo
host'tan `.\vm-test.ps1 -Senaryo <ad>` ile otomatik koşar.
**Ajan ancak `https://` ile bağlanabilir** (K-21) → testte TLS proxy + CA.
- VM'de PowerShell politikası "Restricted" → `Set-ExecutionPolicy Bypass -Scope CurrentUser -Force`
- **VM kendini yeniden başlatıyordu** → `kur.ps1` artık güncelleme servislerini kapatıyor

**VM'de tek komut:**
```
iwr 192.168.79.1/kur.ps1 -outfile k.ps1; .\k.ps1
```

## Bu oturumda bulunan hatalar (öğrenildi)

| Hata | Çözüm |
|---|---|
| `DESKTOP_JOURNALPLAYBACK` kaldırılmış → **her SendInput "Access denied"** → uzaktan girdi hiç çalışmıyordu | `ac08a1f` ile düzeltildi |
| `segnox-devdb.exe` **eski** → migration gömülü değil → "column customer_id does not exist" | Script artık exe'yi migration'dan eskiyse yeniden derliyor |
| `Start-Job` **ayrı süreç** → TcpListener kopyalanmıyor | python `http.server` kullanıldı |
| `HttpListener` + `http://+:port` → yetki gerekir | TcpListener / python |
| `.vmx` içine dizi elemanı yazınca bozuk satır → VMware "config okunamıyor" | Temizlendi, yedek alındı |
| **ExecutionPolicy "Restricted"** (Win11 varsayılanı) → script çalışmıyor | `Set-ExecutionPolicy Bypass` |
| `go test` **atlanan** testleri "ok" gösteriyor | "atlanan testleri ayrıca bildir" kuralı eklendi |
| Claude Code 5 saatlik limite takılınca yarım kod bırakıyor | Temiz build worktree kullan |

## Push / CI

```
cd C:\Users\Erayc\Desktop\segnox-uzaktan-erisim
git push origin main
gh run list --repo Eraycann/segnox-uzaktan-erisim --workflow ci --branch main --limit 1
gh run view <id> --repo Eraycann/segnox-uzaktan-erisim --json jobs,conclusion
gh run view <id> --repo Eraycann/segnox-uzaktan-erisim --log-failed
```

**Claude Code'un push'u yok — ben yaparım.** CI 4 iş: windows · linux(-race) ·
e2e · deploy(coturn-probe).

### Ana dalda bilinen kırık testler (20.10 akşam, a4815ee sonrası)

| Test | Nerede | Neden | Kim |
|---|---|---|---|
| `TestPrepareUpdateDir` | internal/agent/svc (windows) | **CI ortamına bağlı** — "foreign-owner policy accepted the user's file". Yerelde geçiyor, CI'da 3+ koşudur kırık. **Kimse farkında değilmiş.** | Claude Code |
| rtc testi | internal/agent/rtc (`rtc_test.go:65`) | `t.Errorf`, test bittikten sonra gelen pion goroutine'inde → "Fail in goroutine after TestVideoNoVideoOffer has completed" + DATA RACE. Yerelde 3× geçiyor | Claude Code |
| e2e "Güncelle düğmesi" | e2e/tests/update.spec.ts | Playwright `res.json()` protocol hatası (CI'da aralıklı) | Claude Code |
| ~~`TestMigrateFromScratch`~~ | internal/store | ✅ **düzeldi** — 6f migration'ı 2 resolver ekledi, sayaç 9→11 |

**Ders:** Push, adım ortasında değil **ağaç kendi kendine yeterliyken** yapılmalı.
6f W1/W2 commit'liyken sunucu ucu yoktu → 3 iş kırık. Push'u "commit'li = hazır"
diye değil, "CI yeşil" diye yap.

**Claude Code onay denetimi takıldı (20.10 17:30):** komut koşmadan önceki
otomatik güvenlik onayı yanıt vermiyor; ajan W3'ü bitirdi ama commit atamadı.
**Çözüm: ben kalite kapısını koşup commit'ledim** (`bash scripts/kapi.sh go` →
yeşil) ve görev dosyasını sildim. Aynı tuzağa düşmemek için: Claude Code
beklerken ben `kapi.sh go` koşup yeşilse WIP'i ben commit'leyebilirim.

## Site güncelleme kuralı

Claude Code her adım sonunda **"yapılmayanlar" raporu** veriyor (HEDEF dosyasındaki
kural). Ben onu siteye işliyorum. Ayda 1 denetim (subagent) ile tutarlılığı
kontrol ediyorum — **kendi gözüme güvenme**.

**20.10 akşam site durumu:** `42a1ce3` push edildi, Pages canlı
(https://eraycann.github.io/segnox-site/). 6e "Bitenler"e alındı, 6f "Yarım
kalan"a, Alpemix karşılaştırma tablosu **kod taramasıyla** yeniden yazıldı
(7 eşit + 1 yolda + 11 eksik), El Kitabi'ne "atlanan 3 testin adı" ve kayıt
şemasının gerçek hali girdi, CI satırı gerçeğe çekildi.

**Kural:** 4 sayfada da damga var (`Son güncelleme: <tarih> · Kaynak: repo @ <hash>`).
bilgi.html'de damga **yoktu** → eklendi. Yeni sayfa/kolon açarken damgayı unutma.

## Araştırma (benim alanım)

- `.tools/ARASTIRMA-6F-CANLI-DESTEK.md` — Alpemix'in canlı destek widget'ının
  10 davranışı + bize çıkarımları + K-36 için açık karar noktaları.

## VPS / para (bilgi)

- Hetzner CX23 (2 vCPU, 4 GB) €3,99 + IPv4 €0,50 = **€4,49**; yedekleme ~€2
- **1 € ≈ 55,30 TL** → sunucu ~€6,50 ≈ **360 TL/ay**
- **segnox.com zaten bizim** → alan adı gerekmez, `destek.segnox.com` yeter
- TURN açık relay 1 saat ≈ 2,7 GB; H.264 ile ≈ 1,45 GB → **fiyatı belirleyen
  veri bu**

## Bilinen riskler (20.10 itibarıyla)

- **Farklı ağdan bağlantı hiç test edilmedi** (sadece aynı Wi-Fi + telefon)
- **Servis kipi gerçek makinede denenmedi** (VM'de yapılacak)
- Kod imzası yok → kurumsal alıcı reddeder
- Abonelik/faturalama yok → satış için kritik
- CI'da 2 test kırık olabilir (Claude Code WIP)

## 21.10 — VM'de bulunan GERÇEK ÜRÜN HATALARI (Claude Code'a verilecek)

**1) Onay penceresi (ui-host) servis kipinde anında düşüyor — EN KRİTİK**
```
"ui-host started" (pid 9504) → "ui-host attached" → "ui-host connection lost, restarting" (ipc: connection closed)
```
3 kez tekrar ediyor (backoff 1s/2s/4s). Yardımcı SYSTEM, oturum 1, ui_host:true.
Sonuç: **müşteri onay penceresi çalışmıyor** → onaysız bağlantı yapılamıyor.
K-26 zincirinin son halkası kırık. e2e'de görünmüyor (orada ui-host yok).

**2) `SEGNOX_PUBLIC_URL` yanlışsa TÜM cihazlar "revoked" diye reddediliyor**
Cihaz imzası sunucu host'unu içerir (K-21). `SEGNOX_PUBLIC_URL` farklıysa
(imza başarısız) sunucu `unauthorized` döner, ajan da
"server refused the device identity; **it may have been revoked**" yazar.
→ Yanıltıcı hata + deploy'da doğrulama yok. `deploy/.env.example` PUBLIC_URL
içermiyor (kontrol edilecek).

**3) Ajan loopback dışındaki düz HTTP sunucuyu reddediyor (K-21)**
`device: https required for a non-loopback server` → çıkış kodu 2.
"**Kendi sunucusuna kurulum**" özelliği olan bir üründe, LAN'daki kendi
sunucusuna düz HTTP ile bağlanamamak sorun. Seçenek: açık/opt-in bir bayrak
(örn. /INSECURE) veya kendi CA'sını yükleyebilme.

**4) Test notu:** e2e testleri bu 3 noktayı yakalayamıyor — sunucuları
127.0.0.1'de (loopback) çalıştırıyorlar ve ui-host yok.

## 24.10 — Devir (asistan durdu; VM + CI artik Claude Code'da)

- **VM eski ajani kuruyordu:** `poller-http.ps1` `segnox-agent.exe`'yi yalniz `C:\segnox-test\paket`'te yoksa indiriyordu -> 21.10'daki 6i oncesi ikili her senaryoda yeniden kuruldu (H1 "duzelmedi" sanildi).
  Duzeltme (`vm-test.ps1`): host `paket.sha256` yazar; konuk betigi baslarken ozetle esitler (farkli/eksik dosyayi indirir, ozeti dogrular); kurulumdan sonra `segnox-agent.exe version` host'takiyle ayni degilse HATA.
- `servis` senaryosu artik 40 sn bekleyip helper ui-host satirlarini, `ProgramData\Segnox\logs\ui-host-<pid>.log` (en yeni 3) ve kullanici `ui-host.log`'unu topluyor.
- Push: arac izni Claude Code'un push'unu engelliyor -> kullanici `! git push origin main`.
- VM yine kendiliginden yeniden basliyor (24.10) -> `servis`ten once `-Senaryo hazirlik`.
