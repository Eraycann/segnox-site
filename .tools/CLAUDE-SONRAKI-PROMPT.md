# Segnox — Claude Code'a verilecek metin (24.10.2026)

> Kopyala-yapıştır. Push yok (asistan yapar). Bu tur: **2 iş** — ui-host (H1) hâlâ
> kırık + CI'daki kırık test.

---

## 1 · H1 (ui-host) GERÇEK MAKİNEDE HÂLÂ KIRIK

6i'deki boru (pipe) düzeltmesi işe yaramadı. Windows 11 VM'de yeni ajan
kuruldu, kullanıcı oturumu **açık** (explorer.exe session 1, kullanıcı Erayc),
WebView2 **kurulu** (155.0.4283.62). Ajan logu (helper-1.log):

```
"ui-host started","pid":11084
"ui-host attached"
"ui-host connection lost, restarting","err":"ipc: connection closed","backoff":30000000000
... 30 saniyede bir tekrar ediyor (1s,2s,4s,8s,16s,30s)
```

Ek kanıtlar (konukta SYSTEM olarak toplandı):

- **ui-host'un kullanıcı logu HİÇ oluşmuyor**: `C:\Users\Erayc\AppData\Local\Segnox`
  yok; SYSTEM profilinde de yok. Yani `svc.OpenUserLog("ui-host")` hiç dosya
  üretmiyor (ya çağrıya hiç gelinmiyor ya da hata stderr'e gidiyor ve kimse
  okumuyor).
- **Yeni eklediğin çıkış-kodu logu hiç çalışmıyor**: helper-1.log'da
  `ui-host exited` = 0, `exit code unavailable` = 0, `start failed` = 0.
  Yani `stop()` / `logUIHostExit` yolu (bağlantı koptuğunda) hiç işlemiyor.
- Bağlantı **1–50 ms** içinde kopuyor: "started" ile "connection lost" aynı
  saniye. UI hiç kurulmuyor.
- Elle SYSTEM olarak `segnox-agent.exe ui-host -pipe yok -parent <pid>`
  çalıştırıldığında beklenen ret geliyor:
  `"ui-host must run with the logged-on user's token, never as LocalSystem"`,
  çıkış kodu 1. Yani SYSTEM denetimi çalışıyor — ama gerçek launch'ta süreç
  boruya **bağlanıyor** (yani denetimden geçiyor), sonra ölüyor.

**İstenen (bu sırayla):**
1. `uiHostLaunch`'ta `stop()`'un en başına koşulsuz bir log koy; `logUIHostExit`
   neden hiç çalışmıyor, bul (ctx/closure mı, `_ = conn.Close()` sonrası mı
   dönülüyor?).
2. Helper, ui-host'un **stderr'ini bir dosyaya yönlendirsin**
   (`%ProgramData%\Segnox\logs\ui-host-<pid>.log`) ve `.WaitTimeout` sonucunu
   oraya da yazsın. Şu an ui-host'un tek teşhis kanalı kullanıcı logu; o da
   oluşmuyor.
3. Helper, başlattığı sürecin **token kullanıcısını** loglasın
   (`UserTokenForSession` sonucu SID + `StartProcessAsToken` sonrası süreç
   token'ı). Süreç gerçekten Erayc mi, SYSTEM mi — kanıt olsun.
4. `svc.OpenUserLog` hata verirse **helper loguna** yazsın (stderr'e değil).
5. WebView2 kurulu; `newUI` fallback'i var. Yine de `newUI` hatasını helper
   logunda görünür kıl.

**Tekrar üretmek için:** VM hazır (Windows 11, 192.168.79.129, kullanıcı
oturumu açık). Asistan `.\vm-test.ps1 -Senaryo servis` ile yeniden koşar ve
yeni logları toplar.

## 2 · CI kırık: `TestDialSystemCheckWithoutProcessAccess`

`f478cbb` push'unda **windows (build, vet, lint, test)** düştü:

```
--- FAIL: TestDialSystemCheckWithoutProcessAccess (0.00s)
    pipe_windows_test.go:262: precondition: the test process can still be opened
FAIL segnox.com/uzakdestek/internal/agent/ipc
```

Yerelde 5/5 geçiyor; GitHub Actions Windows runner'ında ön koşul sağlanmıyor.
Test ortama bağımlı: ön koşul sağlanmıyorsa `t.Skip` ile atlanmalı (ya da
kendi sürecine `PROCESS_QUERY_LIMITED_INFORMATION` ile açmayı denemeli).
Kırık testle CI yeşile dönmez; push bloke.

## 3 · Kural

- Push yok. Commit'le; asistan push + CI yapar.
- Rapor: ne değişti · yapılmayanlar tablosu · test sonuçları + **atlanan
  testlerin adları** · ACIK-KONULAR · commit sayısı.
- "Atlanan" testleri "geçti" sayma. "Flaky" deme, kök nedeni bul.
