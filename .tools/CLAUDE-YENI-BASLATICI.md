# Segnox — devam (Claude Code, /clear sonrasi)

**Hedef dosya:** `C:\Users\Erayc\Desktop\segnox-site\.tools\HEDEF-ALPEMIX-ESITLAMA.md`

## Ne yapacaksın

1. **Önce sadece şunları oku:**
   - `docs/DEVAM.md` (özellikle "Çalışan işler" tablosu)
   - `git log --oneline -15`
   - `git status --short`

   Başka dokümanı baştan okuma. İş baştan yapılmaz.

2. **"Çalışan işler"deki ajanlar arka planda sürüyor olabilir.**
   Bildirimlerini bekle. Limite takıldıysa tablodaki ajan kimliğiyle
   `SendMessage` ile sürdür: **"önce `git diff`, baştan yapma."**

3. Her ajan bitince:
   - Tablodaki "Bitince" sütununu uygula
   - Commit at
   - Satırı tablodan sil

4. **Sıra:**
   - 6a–6d birleşik raporu (update.spec temiz geçince)
   - 6e hedefli doğrulama → görüntüleyici denetimi → rapor
   - Sonra **6f** (canlı destek widget, K-36 yazılacak)
   - 6g bayi markası, 6h fiyat/plan → **ACIK-KONULAR'a yaz, kullanıcı kararı**

## Her adım sonu raporu (bu formatta)

1. **Ne değişti** — 3-5 madde
2. **Yapılmayanlar tablosu** — planda yazılı ama kodda olmayan her madde,
   kod durumuyla: `var | altyapı var | yok` + adım no
3. **Testler** — kaç geçti, **kaç ATLANDI, atlananların adıyla**
4. **ACIK-KONULAR** — ne eklendi
5. **Push için commit sayısı** — kaç commit bekliyor

## Kurallar

- Türkçe, kısa, liste
- **≤4 paralel ajan**
- **Yüksek/orta güvenlik bulgusu açık kalmaz** (düşük kapanır, gerekçesiyle)
- **Push yapma** — ben yaparım, CI'yı kontrol ederim
- Çalışan `segnox-server` / `segnox-devdb` süreçlerine dokunma
- **Commit'li ağacı doğrulamak için:** `git worktree add --detach <tmp>/wt HEAD`
  → orada build/test → `git worktree remove --force`
  (çalışan ajanların işiyle karışmaz; e2e için `e2e/node_modules` kopyalanır)
- Bağlam dolunca `/clear` hatırlat, **önce DEVAM.md'yi güncelle**

## Bu oturumda çıkan dersler (uygula)

- **"Atlanan" testleri "geçti" sayma.** Gerçek girdi testleri SendInput hata
  verince Skip ediyordu ve `go test` "ok" diyordu. Artık **atlananların adını
  yaz.**
- **"Flaky" deme.** Kök nedeni bul. Üç dalga üst üste aynı kalıpta test
  kırıldı, her seferinde "yük altında" çıktı; biri gerçek ürün hatasıydı
  (`DESKTOP_JOURNALPLAYBACK`).
- **"Tamam" deme, "bitti" de** — kod bitti, kullanıcı denemesi bekliyor.
  `PLAN.md`'de ikisini ayır.
- **Plan yazılı olmak = yapılmış olmak değil.** Bu yüzden her adım sonunda
  yapılmayanlar raporu var. Sitede 12 özellik aylarca "planda" görünüyordu.
