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

## Adım durumu (20.10.2026)

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
| **6e** | **Oturum kaydı (video)** | K-35 | 🔄 **devam ediyor** |
| 6f | Canlı destek widget | K-36 (yazılacak) | ⬜ sırada |
| 6g | Bayi markası | — | ⬜ |
| 6h | Fiyat/plan arayüzü | — | ⬜ **kullanıcı kararı** |
| 7 | Ses, cihaz sağlığı, webhook, Wake-on-LAN, duyarlı izleme | — | ⬜ |
| 8 | Linux ajanı (X11) | — | ⬜ |
| 9/10 | Mobil izleme (A) / Android kontrol (B) | K-29 | ⬜ |

**Karar:** 1–4b + 5a–5f + 6a–6d = **36 özellik tamam**. Kalan 6f/6g/6h + 7 + 8 + 9/10.

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
**#4 Hetzner + DNS** · **#6 kod imzası** · **#7 KVKK avukat** · **#8 fiyat** ·
**#5 SMTP**

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

**VM:** VMware Pro, Windows 11 x64, 4 GB RAM, 4 CPU, NAT (VMnet8)
- VM IP: `192.168.79.129` · host: `192.168.79.1` (VMnet8) / `192.168.1.26` (Wi-Fi)
- **Host→VM yerine VM→host** bağlantısı kurulur (dosya sunucusu)
- Tools ISO: `C:\Program Files\VMware\VMware Workstation\windows.iso`
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
```

**Claude Code'un push'u yok — ben yaparım.** CI 4 iş: windows · linux(-race) ·
e2e · deploy(coturn-probe).

## Site güncelleme kuralı

Claude Code her adım sonunda **"yapılmayanlar" raporu** veriyor (HEDEF dosyasındaki
kural). Ben onu siteye işliyorum. Ayda 1 denetim (subagent) ile tutarlılığı
kontrol ediyorum — **kendi gözüme güvenme**.

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
