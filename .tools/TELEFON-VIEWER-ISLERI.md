# Telefon kullanımı: Backspace/Enter hatası + yakınlaştırma yok

Kullanıcı telefondan bağlandı (aynı Wi-Fi, ikinci cihaz). **Uzaktan fare,
tıklama ve yazı çalışıyor.** İki sorun kaldı.

## 1) Backspace çalışmıyor — gerçek hata

Belirti: telefon klavyesindeki silme tuşu uzak makinede hiçbir şey yapmıyor.

Kök neden: `web/viewer/src/input.ts`, `onInput()`:

```js
if (e.inputType === 'insertText' || e.inputType === 'insertReplacementText') {
  text = e.data ?? this.kbd.value;
} else if (e.inputType === 'insertFromPaste' || e.inputType === 'insertFromDrop') {
  text = this.kbd.value;
}
// insertCompositionText is handled by compositionend; anything else
// (deletions, line breaks) only clears the buffer.
this.kbd.value = '';
if (composed !== null && text === composed) return;
if (this.enabled && text) this.sendText(text);
```

`deleteContentBackward`, `deleteWordBackward`, `deleteByCut` **hiçbir
dallanışa girmiyor** — "anything else" yorumuna düşüp sadece tamponu
temizliyor. Uzak makineye **hiçbir şey gönderilmiyor.**

**`insertLineBreak` de aynı şekilde** — yani Enter de gönderilmiyor. Kullanıcı
sadece silmeyi bildirdi ama bu ikisi aynı kökten.

İstenen:

- `deleteContentBackward` → uzak makinede **Backspace** tuşu (bas-bırak).
  `deleteWordBackward` → Ctrl+Backspace. `deleteByCut` → silinmiş metin.
- `insertLineBreak` → Enter.
- Mobil klavye davranışı: Android/iOS yumuşak klavye `keydown`'u
  `code: 'Unidentified'` veya `keyCode: 229` ile verebiliyor; bu durumda
  `onKey()` erken dönüyor ve her şey `input` olayına düşüyor. Yani
  **deletion/line-break yolu `onInput` içinde doğru ele alınmalı**, yoksa
  mobil klavye hiç çalışmaz.
- `kbd` textarea'sının içeriği her durumda temizlenmeye devam etmeli (buffer
  büyümesin).
- Geri al/yinele (undo) zarar vermemeli.

Test: e2e'de mobil benzeri `inputType` değerleriyle birim testi. Gerçek
tarayıcıda `InputEvent` üretmek zor olduğundan `onInput`'ın işlediği
`inputType` kümesi en azından ayrı bir saf fonksiyona ayrılıp test edilsin.

## 2) Yakınlaştırma / uzaklaştırma yok

Telefonda uzak ekran çok küçük kalıyor, yazı okunmuyor. View'da şu an sadece
`fullscreen` var; **zoom, pan veya ölçek kontrolü hiç yok.**

İstenen:

- Görüntüyü yakınlaştırma/uzaklaştırma (düğme ve/veya pinch-to-zoom).
- Görüntünün bir köşesine sabitlenip kaydırılabilmesi (pan).
- **Kritik:** yakınlaştırıldığında `mapPointer` (input.ts) koordinat
  dönüşümü **ölçeği hesaba katmalı**. Şu an `object-fit: contain` ile
  çizilen kareye göre hesap yapıyor (`const scale = Math.min(rect.width / w,
  rect.height / h)`). Zoom eklenirse bu dönüşüm bozulur ve **tıklama yanlış
  yere düşer** — ki bu tam olarak düzeltmek istediğimiz hata.
- `MOUSE_SCALE` sabit (muhtemelen 32767). Zoom sonrası hassasiyet düşebilir;
  ölçüm gerekebilir.
- Klavye/fare dönüşümü bozulmasın.

## 3) Ek not — kapsam dışı ama not düşülsün

Telefon **hücresel veriden** bağlandığında `192.168.1.26`'ya ulaşamaz (o adres
sadece ev ağında geçerli). Gerçek "farklı ağ" testi ancak gerçek sunucu
(VPS) ile mümkün. Bu, ürün eksiği değil, test ortamı sınırı.

## Kalite kapısı

- Derleme, vet, lint temiz
- Yeni davranış için test (deletion/line-break yolu, zoom koordinat dönüşümü)
- Güvenlik denetimi (düşük bulgular kapatılsın)
- Push yapma
