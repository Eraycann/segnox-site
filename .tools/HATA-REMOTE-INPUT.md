# HATA: uzaktan fare/klavye çalışmıyor — gerçek makinede doğrulandı

## Belirti

Ajan ekranı aktarıyor (H.264 ve JPEG karo), sohbet/ pano / dosya çalışıyor.
Ama **uzaktan fare imleci hareket etmiyor, tıklama ve yazma çalışmıyor.**
Bilgisayardan ve telefondan (ayrı cihaz, `candidate_type: prflx`) bağlanıldığında
da aynı sonuç. Kullanıcı arayüzü "sadece izleme" gibi görünüyor.

## Dışlananlar (kanıtlarıyla)

| Hipotez | Sonuç | Kanıt |
|---|---|---|
| Rol `view` değil `control` mı? | ❌ Değil | Ajan logu: `"session_role":"control"` (iki oturum da) |
| Onay penceresi girdiyi kilitliyor mu? | ❌ Değil | `"remote input paused while a consent prompt is open"` logu **yok** |
| `SendInput` çalışmıyor mu? | ❌ Çalışıyor | `SEGNOX_REAL_INPUT_TEST=1 go test -run TestRealMouseMove` → **3/3 geçti**; P/Invoke ile `SendInput` `1/1` inserted |
| Masaüstü kilitli / başka oturum mu? | ❌ Değil | LogonUI yok; ajan ve explorer SessionId **3**; `TestRealAttachOnInjectionThread` PASS |
| Enjeksiyon arka ucu yanlış mı bağlanmış? | ❌ Doğru | `newInjector("auto")` → `input.Default()` |
| Görüntü kipi (H.264 vs tiles) mi? | ❌ Değil | İkisi de aynı sonuç |
| Cihaz farkı mı? | ❌ Değil | Telefon (`prflx`) ve bilgisayar (`host`) aynı |

Tarayıcı tarafı da doğrulandı (bilgisayarda konsoldan):

```json
{"durum":"connected","rol":"control","w":1920,"h":1080,"kip":"h264","yol":"host","hata":null}
```

`main.ts:346` → `input.setEnabled(s === 'connected' && role === 'control')` → **true olmalı.**
`input.ts:134` → `onPointerDown` yalnız `this.enabled` kontrolü yapıyor.

## Dumanı çıkaran yer

`internal/agent/session/session.go`, `handleControl` sonu:

```go
if ierr != nil {
    s.log.Debug("input injection failed", "type", env.Type, "err", ierr)
    return nil
}
```

**Enjeksiyon hatası `Debug` seviyesinde loglanıyor ve `main.go:36`
`slog.NewJSONHandler(os.Stderr, nil)` ile Info seviyesine sabitlenmiş —
yani bu mesaj ASLA görünmüyor. Ajanın log seviyesini yükseltecek ortam
değişkeni yok.**

Sonuç: "fare çalışmıyor" durumunda elimizde hiçbir sinyal yok.
Görüntü akıyor, rol doğru, sohbet çalışıyor, ama enjekte etme sessizce
başarısız olabiliyor.

## İstenen

1. **Log seviyesini yapılandırılabilir yap.** Ajan log'a `SEGNOX_LOG_LEVEL`
   (veya benzeri) eklesin; `debug` değerinde `input injection failed` görünsün.
   Alternatif: bu mesajı en az `Warn` seviyesine çıkar. Sessiz veri kaybı
   (`return nil`) kabul edilemez — en azından sayac/telemetri koyulmalı.

2. **Enjeksiyon hatası oturumu bitirmemeli ama kaydedilmeli.** Şu an
   `return nil` ile yutuluyor; `bad` sayacına da girmiyor.

3. **Kök nedeni bul.** Yukarıdakiler geçtiğine göre iki olasılık kaldı:
   - a) `input.mouse` mesajları ajana hiç ulaşmıyor (tarayıcı tarafında
     `enabled` true olmasına rağmen `pointerdown` canvas'a ulaşmıyor olabilir —
     örtücü bir element, `kbd.focus()` başarısızlığı, `mapPointer`
     koordinat dönüşümü). Sohbet çalıştığı için kanal sağlam, ayrım burada.
   - b) Mesajlar ulaşıyor, `inj.MouseMove()` / `inj.MouseButton()` hata
     dönüyor ama hata görünmüyor.

   Bunu ayırmak için **aşama 1'in log seviyesi şart.** Log açılınca
   `input injection failed` satırı görünecekse (b), görünmeyecekse (a).

4. **Yarış testi yaz.** `TestICERestartAfterFailure` ve
   `TestPendingRequestTimesOut` gibi iki dalga üst üste aynı kalıpta
   (test kırıldı, kök neden bulundu) bu da sessiz veri kaybı olabilir.
   "remote input" yolunda mesaj gönder → ajan tarafında enjekte edilmiş
   olduğunu doğrulayan bir e2e/integrasyon testi olsun. Var mı, kontrol et;
   yoksa ekle.

## Ortam notu

- Test makinesi: Windows 11 Home, Build 26200, VMware Pro + Kali + Windows 11 VM açık
- `CGO_ENABLED=0` kalite kapısı hâlâ geçerli
- Push yapma