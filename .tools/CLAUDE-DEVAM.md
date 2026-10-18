# Segnox — Durum devam notu (pazarlık → sana)

## Ne yapıldı (bugün, elle deneme)

Kullanıcı MVP'yi kendi bilgisayarında çalıştırdı. Tamamlananlar:

1. **devdb + sunucu + ajan yerelde ayağa kalktı.**
   `SEGNOX_DATA_KEY` için openssl yoktu; PowerShell `RandomNumberGenerator`
   ile üretildi. Bu site örneğine not düşüldü.

2. **Gerçek masaüstü doğrulaması.** `capture backend selected: dxgi`
   → donanım yakalama sürücüsü gerçekten çalışıyor, GDI'ye düşmüyor.
   WebView2 155 onay penceresi açılıyor. Sinyal sunucusu bağlantıyı
   kabul ediyor.

3. **Elle test edilen özellikler:** sohbet, ortak pano, dosya transferi,
   kapatılamayan bilgi çubuğu — hepsi çalışıyor.

4. **Bulunan ve düzeltilen hata: fare imleci.** `PointerX/PointerY/PointerVisible`
   hiç okunmuyordu, kareye imleç çizilmiyordu. Senin commit'inle düzeltildi.
   Henüz gerçek masaüstünde yeniden doğrulanmadı.

5. **Bulunan ve düzeltilen hata: TURN tüm IPv4'ü reddediyordu.**
   `deploy/coturn/turnserver.conf` içindeki `::` ile başlayan IPv6
   aralıkları, coturn'ün IPv4-mapped temsiliyle çakışıp 8.8.8.8'i de
   reddediyordu. Düzeltildi, CI'de yeşil.

6. **CI tamamen yeşil** (senin push'un + benim push'um sonrası):
   windows · linux · e2e · deploy(coturn-probe) — dördü de success.

7. **Bulunan hata: TURN adresi doğrulanmıyor.** `SEGNOX_TURN_URLS`
   için sadece "turn: ile başlıyor mu" bakılıyor. Kullanıcı yer tutucu
   yazınca (`turn:127.0.0.1:PORT?transport=udp`) sunucu sessizce kabul
   edip oturumda `InvalidAccessError: invalid port` verdi.

8. **Bulunan hata: trustedProxies=0 iken gerçek IP kayboluyor.**
   Tüm bağlantılar `ip: 127.0.0.1` görünüyor. Bu, IP başına hız sınırının
   tüm kullanıcıları tek yerden sınırlamasına yol açar.

## Şu anki durum — KULLANICI DANIŞMIYOR

Kullanıcı sunucu kiralamak istemiyor. Elimizde sadece **cloudflared hızlı
tüneli** var (`https://hopkins-join-gordon-mattress.trycloudflare.com`).
Bu yalnızca HTTP/8080'i dışarı açar. **UDP'yi tünelleyemez.**

Açık pencereler: `segnox-devdb` · `cloudflared` · `segnox-devturn`
· `segnox-server` (TURN env ile) · `segnox-agent`.

Denenen yollar ve sonuçları (`support_sessions` tablosundan):

| Zaman | Süre | Yol | fps | Bayt | Durum |
|---|---|---|---|---|---|
| 02:57:51 | 110s | host | 17,4 | 75,2 MB | çalıştı (aynı ağ) |
| 02:59:56 | 33s | host | 22,4 | 36,7 MB | çalıştı (aynı ağ) |
| 03:00:35 | 48s | **srflx** | 15,4 | 37,4 MB | belirsiz (kimin?) |
| 03:01:35 | 17s | — | 0 | 0 | başarısız |
| 03:04:59 | 16s | — | 0 | 0 | başarısız |
| 03:05:55 | 17s | — | 0 | 0 | başarısız |

**Kullanıcının ifadesi:** "Arkadaşım bağlanmaya çalıştı ve aynı hata
ona da geldi." Sonra netleştirdi: **arkadaş ev Wi-Fi'sindeydi ve o da
bağlanamadı.**

**Bilinmeyen:** 03:00:35'teki srflx kaydı kimin denemesi. Loglarda
kullanıcı kimliği veya kaynak (telefon/bilgisayar) yazmıyor.

**Önemli:** Arkadaşın ev Wi-Fi'si de başarısız olduğuna göre sorun
CGNAT'a özgü değil — daha geniş bir sorun.

## Takıldığımız yer

**Kullanıcının arkadaşı ev Wi-Fi'sinden de bağlanamadı — hücresel veriyle
aynı hata.** Yani sorun "CGNAT'a özgü" değil, daha geniş.

### Bulduğum önemli bir eksik

Sunucu çıktısında **`"stunServers":0`**. Yani **hiç STUN sunucusu
tanımlı değil.** `SEGNOX_STUN` ortam değişkeni mevcut
(`cmd/segnox-server/config.go:73`) ama hiç set edilmedi.

Bu neden önemli: ICE aday toplama (candidate gathering) srflx adaylarını
ancak bir STUN sunucusu üzerinden keşfeder. STUN olmadan sadece `host`
adayları (yerel arayüzler) toplanır.

Ama 03:00:35'te bir `srflx` adayı **seçilmiş**. Muhtemelen yerel
`segnox-devturn` aynı UDP portunda STUN binding isteklerine de yanıt
verdiği için aday keşfi mümkün olmuş (TURN ve STUN aynı portu paylaşır).
Bu, o kaydın tesadüfi çalıştığını düşündürüyor.

**Arkadaşın başarısız olmasının olası sebepleri** (hangisi doğru
bilinmiyor, ölçülmedi):
- Türkiye'de ev interneti operatörlerince sıklıkla **CGNAT** ile veriliyor —
  yani "ev Wi-Fi'si" de fiilen CGNAT olabilir
- NAT tipi **simetrik** ise srflx adayına dışarıdan ulaşılamaz
- Ağ UDP'yi tümüyle engelliyor olabilir

### A) TURN dışarıdan erişilemiyor (kesin doğru)

Sunucu `SEGNOX_TURN_URLS=turn:127.0.0.1:64309?transport=udp` ile
çalışıyor. Bu adres **istemcinin kendi** 127.0.0.1'i. Telefonda
`127.0.0.1` telefonun kendisi demek, orada TURN yok. Aynı bilgisayarda
olduğu için de `turncred.PeerAllowed` reddi gerekçesiyle
`-allow-loopback-peers` gerekiyor.

**Sonuç: yerel devturn dışarıdan hiçbir istemciye hizmet veremez.**
TURN'in kendisi CI'da doğrulandı ama uçtan uca hiç denenmedi.

### Özet: iki eksik var

| | Durum | Etki |
|---|---|---|
| **STUN sunucusu** | tanımlı değil (`stunServers:0`) | srflx adayları güvenilir keşfedilmiyor |
| **TURN erişilebilirliği** | sadece `127.0.0.1` | CGNAT/simetrik NAT'ta hiçbir yol yok |

**Sunucu parası harcanmadan** ikisi de çözülebilir mi, senin araştırmanın
konusu.

## Senin kıymetli bulmanı beklediğim konu

Sunucu parası harcanmadan (en azından kısa vadede) **internet üzerinden
bir uçtan uca test yapılabilir mi?** Şunları değerlendir:

1. **TURN/TCP-TLS dinleyicisi eklenebilir mi?**
   `internal/testutil/turnserver/turnserver.go` yalnızca UDP dinliyor
   (`ListenPacket` udp4, satır ~74). Pion `turn.PacketConnConfigs`
   birden fazla dinleyici kabul ediyor. TURN/TCP-TLS (RFC 6062) eklerse
   TURN'yi `turns:...` olarak **443/TCP üzerinden** tünellenebilir —
   ve 443 tünellemesi cloudflared ile mümkün.
   cloudflared hızlı tüneli doğrudan TCP açmıyor; `cloudflared access tcp`
   (ücretsiz hesap + adlandırılmış tünel) mümkün olabilir. Araştır, denenecekse
   deneme adımlarını yaz.

2. **Gerçek STUN sunucusu.** `SEGNOX_STUN` ile genel bir STUN
   (ör. `stun:stun.cloudflare.com:3478`) verilirse srflx adayları doğru
   keşfedilir. Bu, bir kere yapılıp kalıcı ayar olur. Ücretsiz STUN'lar
   güvenilir mi, yoksa kendi sunucumuzda (coturn) STUN açmak mı daha
   doğru? K-10'da bu değerlendirilmiş miydi?

3. **`RelayAddressGeneratorStatic` darboğaz mı?** Yerelde her şey
   loopback olduğu için statik generatör yeterli. Gerçek dağıtımda çok
   IP'li sunucuda `RelayAddressGeneratorNone` ya da
   `RelayAddressGeneratorPortRange` gerekebilir.

4. **TURN adresi doğrulaması** eksik (yukarıdaki madde 7) — başlangıçta
   reddedilmeli, oturumda patlamamalı.

5. **Kayıtlarda kim/ne ayırt edicisi yok.** `support_sessions` tablosuna
   istemci türü (telefon/bilgisayar), kullanıcı ajanı, ağ tipi gibi
   en az bir tanımlayıcı eklenmeli. Bugün hangi oturumun kimin
   olduğunu ayırt edemedik — bu analizde işimize yaradı.

6. **trustedProxies / X-Forwarded-For** (yukarıdaki madde 8).

7. **NAT tipi ölçümü.** ICE aday toplarken hangi ağ tipi bulunduğu
   (host/srflx/prflx/relay) kaydedilmeli. Bugün "srflx mı CGNAT mı"
   ayrımını yapamadık. K-48 `LoopbackOnly`/`RelayOnly` bayrakları
   var — bunlar testlerde ayrımı kolaylaştırır mı?

## Nasıl gözlemleyebilirsin

Açık terminallerin çıktısına erişimin yok — PowerShell başka bir
pencerenin stdout'unu vermez. Ama iki yol var:

**1. Veritabanı (en güvenilir).** Sunucu `support_sessions` ve
`audit_log` tablolarına yazıyor. Sahibi DSN ile bağlanıp sorgulayabilirsin:

```
SEGNOX_DB_URL=postgres://postgres:d7b8a1c6df988c50a2f65aa0a07e9f6b@127.0.0.1:52772/segnox?sslmode=disable
```

Not: **uygulama rolü (`segnox_app`) sorguyu boş döndürür** — RLS
devrede, `app.tenant_id` ayarlanmadan hiçbir satır görünmez. Bu beklenen
davranış (izolasyon çalışıyor), hata değil. Rapor için sahibi kullan.

Sorgulanacak tablolar:
- `support_sessions(id, role, started_at, ended_at, end_reason,
  candidate_type, bytes_sent, avg_fps)`
- `audit_log(at, actor_type, action, target, ip, details)`
- `devices(name, os, agent_version, last_seen_at)`

**2. Süreçler.** `Get-Process | ? ProcessName -match 'segnox|cloudflared|postgres'`
çalışıyor mu diye bakılabilir.

Kullanıcı ekran çıktısını sana yapıştıracak — **istediğin an sor.**

## Kural

Kodla ilgili hiçbir değişikliği ben yapmıyorum. Tüm kod, doküman ve
commit senin. Ben yalnızca: siteyi güncelliyorum, push yapıyorum,
araştırma yapıyorum, kullanıcının testlerini yönlendiriyorum.