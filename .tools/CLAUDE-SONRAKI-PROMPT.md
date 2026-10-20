# Segnox — devam promptu (Claude Code için)

> Hazırlandı: 20.10.2026 akşam. Kullanıcı bunu **elle Claude Code'a yapıştıracak**.
> Push yok. Site asistanın işi. Kod senin.

---

## 1 · Nerede kaldık

| Adım | Durum |
|---|---|
| 5a–5f, 6a–6d | ✅ bitti, raporlandı (e2e 29 geçti / 3 atlandı / 0 kaldı) |
| **6e (K-35) oturum kaydı** | ✅ **bitti** — kod commit'li (`deb5906` REC3, `3119366` Tur A denetimi, `14c2a3b`), PLAN'da "bitti", rapor verildi |
| **6f (K-36) canlı destek düğmesi** | 🔄 W1 (betik `583aa70`) + W2 (konsol `bb23837`) + **W3 (sunucu `a4815ee`)** commit'li. **Sırada: W4 e2e → Tur B denetimi → 6f raporu** |

**6f W3'ü asistan commit'ledi.** Sebep: W3 ajanı (kimlik `a55b98dbb1b5244ab`) işini
bitirdi ama komut onayı yanıt vermediği için kalite kapısını koşup commit atamadı.
Asistan `scripts/kapi.sh go` çalıştırdı → **build + vet + golangci-lint + go test
36 paket = yeşil**, sonra `a4815ee` commit'ini attı. `docs/gorevler/6f-W3-sunucu.md`
silindi (`c21c9da`).

**6e rapor özeti (K-35):** görüntüleyicide kayıt (WebM, 5 sn parça, sıralı
yükleme), kiracı anahtarıyla AES-GCM, politika off/optional/required (oturum
başında sabit, `session.accepted` ile), required fail-closed, müşteriye sunucu
kaynaklı `record.notice` (gidemezse 409), izleyici yalnız kendi kaydını yazar,
konsol Kayıtlar (izle/indir/sil), saklama + kısaltma, boş alan 5 GB, Range 416,
audit 10 dk. Denetim: 4 orta + 4 düşük kapandı. Atlanan testler:
`customers.spec` "K-30 watch isteği rolü view olur", `demo.spec` "monitör seçimi",
`real-input.spec` "gerçek enjeksiyon". ACIK #19 KVKK kayıt metni.

---

## 2 · Ana dalda 3 kırık test (CI kırmızı) — teşhisleri hazır

`gh run list --repo Eraycann/segnox-uzaktan-erisim --workflow ci --branch main`
→ son koşu `a4815ee`: **3 iş kırık** (deploy yeşil).

### 2.1 `TestPrepareUpdateDir` — `internal/agent/svc` (windows)
```
update_windows_test.go:109: foreign-owner policy accepted the user's file
```
**Ortam kaynaklı.** Yerelde geçiyor (`go test ./internal/agent/svc/` → ok), CI
runner'ında kırık. **En az 3 CI koşusundan beri kırık, kimse farkında değilmiş.**
Testin varsayımı: "kullanıcının dosyası foreign-owner politikası tarafından
reddedilmeli". CI runner'ında sahiplik beklenenden farklı çözülüyor
(runner kullanıcısı/sahibi). Düzeltme: testi ortamdan bağımsız hâle getir
(kendi dosyanı oluşturup sahipliği değiştir, ya da runner'da policy'yi test etmek
yerine yardımcı fonksiyonu doğrula) — **"CI'da skip" en son çare**.

### 2.2 `internal/agent/rtc` — linux (-race)
```
WARNING: DATA RACE
panic: Fail in goroutine after TestVideoNoVideoOffer has completed
  segnox.com/uzakdestek/internal/agent/rtc.negotiate.func2()
      internal/agent/rtc/rtc_test.go:65
  github.com/pion/webrtc/v4.(*ICEGatherer).Gather.func1()
```
**Kök neden:** `negotiate` yardımcısındaki `viewer.OnICECandidate` geri çağrısı
`rtc_test.go:65`'te `t.Errorf` çağırıyor. pion'un `ICEGatherer.Gather` goroutine'i
test bittikten sonra da tetiklenebiliyor → `testing` paketi "Fail in goroutine
after test has completed" paniği + data race. Yerelde 3× geçiyor, CI'da
(paralel paket yükü altında) patlıyor. Düzeltme: goroutine'i test bitmeden
durdur (kapanış kanalı + `t.Cleanup`), `t.Errorf` yerine senkron bir hata
kanalı kullan.

### 2.3 e2e "Güncelle düğmesi" — `e2e/tests/update.spec.ts`
```
Error: response.json: Protocol error (Network.getResponseBody):
No data found for resource with given identifier
  expect(res.status()).toBe(200);   // 308 geçiyor
  expect(await res.json()).toEqual({ sent: true });  // 309 patlıyor
```
**Playwright/Edge protokol hatası:** `res.json()` gövdeyi alamıyor (CI'da
aralıklı; `waitForResponse` + `reload` yarışı). Daha sağlam okuma:
`page.request.post(...)` veya `res.body()` + `JSON.parse`, ya da yanıtı
tarayıcı bağlamında `fetch` ile al. 30 sn → 60 sn bekleme uzatması yetmedi
(aralıklı kalıyor).

**Yerel doğrulama:** `go test ./internal/agent/rtc/ -count=3` → ok.
`go test ./internal/agent/svc/ -run TestPrepareUpdateDir` → ok.

---

## 3 · Komut onayı sorunu (seni durdurdu)

`bash scripts/kapi.sh go` çalıştırmadan önce gelen otomatik güvenlik onayı
**art arda yanıt vermiyor**. 20.10'da W3 bu yüzden kapıdan geçemedi.
- Bir kez daha dene: onay penceresi gelirse **"Evet"e bas**, `kapi.sh go` koş.
- Yanıt gelmezse: kalite kapısını atlayıp commit atma — durumu `docs/DEVAM.md`'ye
  yaz, asistan `kapi.sh go`'yu koşup yeşilse commit'ler (bugün öyle oldu).
- Kullanıcı bu onay mekanizmasını düzeltiyor; "devam" derse devam et.

---

## 4 · Sıradaki işler (6f)

1. **W4 e2e** — `docs/gorevler/6f-W4-e2e.md` (sonnet / düşük efor):
   `e2e/tests/widget.spec.ts` — ziyaretçi formu → konsol "Siteden gelenler"
   → 9 haneli kod → bağlanma; köken (Origin) reddi, bot tuzağı, istek limiti,
   imzasız indirme reddi.
2. **Tur B denetimi** (`docs/gorevler/denetim-6e-goruntuleyici-6f.md`, opus/high):
   W3'ün kararları — `OPTIONS ?key=` yoksa her biçimli Origin'e yanıt (asıl
   denetim POST'ta), `message` alanında yalnız `\n\r\t` serbest, ad/telefonda
   tüm kontrol karakterleri reddediliyor.
3. **PLAN 6e/6f satırı güncelle**, K-36'ya uygulama notu ekle, **6f raporu** ver
   (yapılmayanlar tablosu + atlanan testler + ACIK-KONULAR).
4. `docs/gorevler/` dosyalarını bitince sil.

**6f sonrası sıra** (HEDEF dosyasına göre): **6h** fiyat/plan → `docs/ACIK-KONULAR.md`'ye
madde (plan/limit tablosu kodda var; ödeme sağlayıcı, KDV/fatura, deneme süresi
**kullanıcı kararı**) → **6g** bayi markası (önce K-37 taslağı: CMX/CM gibi
logo + ad + renk + alan adı; ajan EXE'de marka) → sonra 7. adım.

---

## 5 · Windows 11 VM testi — artık tam otomatik

Kullanıcı "VM'de denenmedi" olan her şeyi gerçek makinede denemek istiyor.
**Sen kod yazma; test betiklerini yaz.** Altyapı hazır:

- VM: VMware Workstation Pro 26.0.1 · Windows 11 x64 · 4 GB RAM · 4 vCPU ·
  NAT (VMnet8) · konuk IP `192.168.79.129` · host `192.168.79.1`
- **VM şifreleme parolası: `windows11`** · `vmrun -T ws -vp windows11 <vmx> ...`
- Konuk kullanıcı: `Eraycansivri@hotmail.com` (Microsoft hesabı) — **parola
  bilinmiyor, Guest Operations (vmrun -gu/-gp) ÇALIŞMIYOR.** Bu yüzden
  otomasyon **paylaşımlı klasör + SYSTEM zamanlanmış görev** üzerinden:
  - Paylaşım: `\\vmware-host\Shared Folders\segnox-calisma` (yazılabilir) ve
    `\\vmware-host\Shared Folders\segnox-paket` (salt okunur) — **HGFS çalışıyor**
  - Konukta `C:\segnox-test\poller.ps1` → `SegnoxVMTest` zamanlanmış görevi
    (SYSTEM, 1 dakika) paylaşımdaki `calis.ps1`'i alıp çalıştırır, çıktıyı
    `...\segnox-calisma\sonuc\calis.log`'a yazar
  - Host tarafı: `.tools/vm-test.ps1` (sunucu + DB + katılım kodu üretir, betiği
    paylaşıma yazar, sonucu bekler)
- Kopyala-yapıştır **çalışıyor** (yeniden başlatmadan sonra).

**Senden istenen:** test senaryolarını `calis.ps1` olarak yaz (konukta SYSTEM
olarak çalışacak, `ProgramData\Segnox` ve ajan loglarını okuyup paylaşıma
yazacak). Sıralı adımlar:
1. `servis` — ajanı `/S /TOKEN=...` ile **servis olarak** kur, **SYSTEM olarak
   çalıştığını kanıtla** (`Get-Process -IncludeUserName`), `ProgramData\Segnox`
   ACL'sinin yalnız SY/BA/Administrators olduğunu göster (K-26).
2. `siyah` — siyah ekran kipinin gerçek masaüstünde çalıştığı (#16, K-32) —
   **gözle kontrol gerekir**, otomatik kısım + ekran görüntüsü.
3. `izleyici` — çoklu izleyici (#18, K-34) — gözle kontrol.
4. `guncelleme` — otomatik güncelleme (#17, K-33): host'ta `segnox-release`
   ile imzalı manifest yayınla, konukta ajanın güncellemesini bekle, geri alma
   yolunu doğrula.
5. `devam` — yeniden başlat + devam (K-27, #14): konuğu yeniden başlat, oturumun
   müşteri onayı sormadan sürdüğünü doğrula.

**Kural:** Windows Update'i ve otomatik yeniden başlatmayı **önce** kapat
(VM kendini yeniden başlatıyordu — `wuauserv`, `UsoSvc`, `WaaSMedicSvc`).
Konuk betiği `C:\segnox-test\` altında çalışmalı, çıktıyı
`\\vmware-host\Shared Folders\segnox-calisma\sonuc\` altına yazmalı.

---

## 6 · Kurallar (değişmedi)

- **Push yok.** Adımları bitince commit'le, push'u asistan yapar, CI'ı o okur.
- Her adım sonunda: **ne değişti** · **yapılmayanlar tablosu**
  (`| Özellik | Plan adımı | Kod durumu | Not |`) · **test sonuçları + atlanan
  testlerin adları** · **ACIK-KONULAR eklemeleri** · **push için commit sayısı**.
- **"Atlanan" testleri "geçti" sayma.** `go test` çıktısında atlanan testleri
  isimleriyle yaz.
- **"Tamam" deme, "bitti" de** — kod bitti, kullanıcı denemesi bekliyor.
  `PLAN.md`'de ikisini ayır.
- **"Flaky" deme, kök nedeni bul.** (Yukarıdaki 3 test için kök nedenler yazılı.)
- `docs/DEVAM.md` ≤ ~40 satır tut; biten işi orada tutma (git + PLAN + KARARLAR'da).
- Aynı dosyaya asistanla dokunma: **kod = sen, site = asistan.**

---

## 7 · Siteye işlenecekler (asistan yaptı, senin yapacağın bir şey yok)

- 6e "Bitenler"e alındı (K-35, denetim 4 orta + 4 düşük kapandı)
- 6f "Yarım kalan"a alındı (K-36, W3 bitti)
- Alpemix karşılaştırma tablosu **kod taramasıyla** yeniden yazıldı:
  **7 özellikte eşitlendik, 1'i yolda, Alpemix'te var bizde olmayan 11 madde**
  (ses, bayi markası, bölge paylaşma, çevrimdışı/duyuru mesajı, grup sohbeti,
  şirket dışı iletişim engeli, ekran işaretleme, mobil, Linux, Mac/iOS, fiyat)
- El Kitabı'na: atlanan 3 testin adı, kayıt şemasının gerçek hali, CI satırı
- Mimari'ye: "dördüncü yüzey — canlı destek düğmesi" kartı
- Site: `https://eraycann.github.io/segnox-site/` (damga: `a4815ee`)
