# 6f araştırması — Canlı destek widget (Alpemix "Web Canlı Destek")

> Kaynak: alpemix.com/tr/web-sitenizden-canli-destek-verin (20.10.2026).
> Amaç: K-36 kararını yazmadan önce rakibin davranışını netleştirmek.
> **Kod yazmıyorum** — bu dosya Claude Code'un 6f adımına girdi.

## Alpemix'in yaptığı (doğrudan kaynaktan)

| # | Yetenek | Alpemix davranışı |
|---|---|---|
| 1 | Web sitesi ziyaretçisiyle canlı yazışma | Widget sitenin içine gömülü |
| 2 | Yazışırken ziyaretçinin bilgisayarına bağlanma | Destek personeli bir **link** gönderir → ziyaretçinin bilgisayarına **özel Alpemix uygulaması iner** → uygulamada uyarı çıkar → "Tamam" deyince teknisyen **otomatik bağlanır** (yalnız Windows) |
| 3 | Çevrimdışıyken | Ziyaretçi **mesaj bırakır** |
| 4 | Birden fazla destek personeli | Alt kullanıcı adları; her biri için **Alpemix Pro** hakkı gerekir |
| 5 | Entegrasyon | **1 satır** `<script>` — `FirmaAdi`, `Departman`, `Param1`, `Param2` parametreleriyle |
| 6 | Yetkili yoksa | Ziyaretçiden **Ad Soyad / Telefon / Email** istenir; alanlar **değiştirilebilir**; web ekranında **firma logosu** |
| 7 | Otomatik başlatma | Alpemix'e giriş yapınca web destek uygulaması otomatik açılabilir |
| 8 | Departman yönlendirme | Ziyaretçi **departman seçer**; sadece o departmandaki personel ilgilenir; `Departman` parametresiyle seçim otomatik atlanabilir |
| 9 | Özel parametreler | `Param1`/`Param2` → yazılım lisans no vb. teknisyene sohbet içinde görünür |
| 10 | Platform | Web + Android + iOS destek personeli uygulaması |

## Bizim için çıkarımlar

**Alpemix'in widget'ı bir "sohbet + yardım masası" ürünü.** Segnox zaten
sohbet + destek kuyruğu + cihaz envanteri + raporlama yapıyor. Yani 6f,
Alpemix'e özgü bir şey değil; bizim **mevcut kuyruğu web'e açmak**.

**Bizi Alpemix'ten ayıran 4 fark (korunacak) 6f'da da geçerli olmalı:**
- Ziyaretçinin bilgisayarına **EXE indirmesine gerek kalmamalı** → tarayıcı
  üzerinden WebRTC ile ekran paylaşımı (bizde zaten var).
- Widget'ın gömüldüğü sayfa **RLS izolasyonuna** tabi olmalı.
- Widget üzerinden yapılan her eylem **hash zincirli denetim kaydına** girmeli.
- Cihaz parolası sunucuya gitmemeli (widget'ta parola hiç olmamalı).

**Açık karar noktaları (K-36'ya gidecek):**
1. Widget tek başına mı, yoksa **"bağlan" akışı** ile birlikte mi?
   (Alpemix'te bağlanma link göndererek + EXE indirerek oluyor. Bizde tarayıcıdan
   olabilir → **Alpemix'ten farklı ve daha iyi**.)
2. **Departman yönlendirme** (Alpemix'in 8. madde) bizde 6g bayi markasıyla
   mı bağlanır, yoksa ayrı mı?
3. Widget'ı **kendi sunucumuzda** mı barındıracağız, yoksa `destek.segnox.com`
   üzerinden mi dağıtacağız? (6g bayi markası → ayrı alan adı gerekebilir.)
4. Ziyaretçi **kimlik doğrulaması** yapar mı, yoksa **anonim** (oturum kodu) mu?
   RLS'in hangi sütununa oturacak?
5. Destek personeli **çevrimdışıyken** ziyaretçiye ne olur? (Alpemix: mesaj bırakır.)

**Bağımlılık zinciri:** 6f → 6g (bayi markası, widget'ın markalanması) → 6h (fiyat).
6f'yi markasız (tek marka) yapıp 6g'de beyaz etiketlemek daha düşük riskli.

**Sıra önerisi:** 6f'i Alpemix'in **1 ve 3. maddeleriyle sınırlı** tut
(canlı yazışma + çevrimdışı mesaj bırakma), bağlanma akışı için tarayıcıdan
çalışan "yardım masası" yeterli. Departman/logo/Param1-Param2 6g'ye bırakılabilir.
