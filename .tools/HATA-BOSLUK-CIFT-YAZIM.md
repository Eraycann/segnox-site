# HATA: telefonda boşluk tuşu yazıyı iki kez yazıyor

## Belirti

Telefondan bağlanıp yazarken, **boşluk (space) tuşuna basınca yazılan metin iki kez
yazılıyor.** Örnek: "abc" yazmak isterken "abcabc" çıkıyor.

Geri al/yinele, kesme, Enter, silme, yakınlaştırma, kaydırma, tıklama —
hepsi düzgün çalışıyor. Sadece boşlukta çift yazım var.

## İlgili kod

`web/viewer/src/input.ts`

```js
// onCompositionEnd
private onCompositionEnd(e: CompositionEvent): void {
  this.composing = false;
  this.justComposed = e.data || null;
  if (this.enabled && e.data) this.sendText(e.data);
  this.resetBuffer();
}

// onInput
private onInput(e: InputEvent): void {
  if (e.isComposing || this.composing) return;
  const composed = this.justComposed;
  this.justComposed = null;
  const act = inputAction(e.inputType, e.data, this.kbd.value);
  this.resetBuffer();
  if (!this.enabled) return;
  if (act.kind === 'text') {
    if (act.text && !(composed !== null && act.text === composed)) this.sendText(act.text);
  } else if (act.kind === 'keys') {
    tapKeys(this.send, act.codes, act.mods, this.keys);
  }
}

// inputAction (dosyanın üst kısmı, saf fonksiyon)
case 'insertText':
case 'insertReplacementText':
  return { kind: 'text', text: data ?? stripSentinel(value) };
```

`SENTINEL = ' '` — gizli kutuda hep bir boşluk tutuluyor (Android klavyeleri
boş alanda silme olayı üretmediği için).

## İki hipotez (biri doğru)

### H1 — `data === null` düşünce tüm birikmiş metin gönderiliyor

`inputAction` `insertText` için `data ?? stripSentinel(value)` kullanıyor.
Android klavyeleri `data` vermediğinde **textarea'nın tamamı** gönderiliyor.
`resetBuffer()` her olaydan sonra çağrıldığı için bu genelde tek karakter
kalıyor — ama **bekleyen bir bileşik (composition) metni varsa** tamamı
gönderilebilir.

"abc" + boşluk → "abc" (bileşik olarak commit) + "abc " (textarea yedeği) =
**"abcabc "** — belirtiyle birebir.

### H2 — `justComposed` koruması tam eşleşme karşılaştırıyor

```js
!(composed !== null && act.text === composed)
```

Koruma **yalnızca metin birebir aynıysa** bastırıyor. Bileşik metin
`"abc"` iken gelen echo `"abc "` (boşluk eklenmiş) ise `===` tutmuyor ve
**metin ikinci kez gönderiliyor.**

Bileşik (composition) Android klavyelerinde yazarken normal; boşluk
bileşiği bitirdiği için fark burada ortaya çıkıyor.

> Her iki hipotez de aynı kökten besleniyor: **"metin ne zaman gönderildi"
> durumu güvenilir değil.** `justComposed` tek bir string tutuyor; hem
> "hangi metin gönderildi" hem "hangi olaydan sonra susturulmalı" bilgisi
> taşımıyor.

## İstenen

1. **Kök nedeni bul ve düzelt.** Boşlukta çift gönderim kesinlikle gitmeli.
   - `data === null` yolunda **sadece yeni eklenen kısım** gönderilmeli,
     textarea'nın tamamı değil. (Sentineel `stripSentinel` mantığı zaten
     "değerin başında/sonunda tek bir boşluk" varsayıyor — birikmiş metni
     ayırmak için gerçek bir "önceki değer" karşılaştırması gerekiyor.)
   - `justComposed` koruması **birebir eşleşme** yerine "bileşikten hemen
     sonra gelen echo"yu susturacak şekilde kurulmalı (örneğin: bileşik
     commit edildiyse, bir sonraki `input` olayı onun yankısı sayılmalı).
   - `onKey` (fiziksel tuş yolu) ile `onInput` (metin yolu) **aynı karakteri
     iki kez göndermemeli**. `onKey` `e.preventDefault()` çağırıyor ama
     Android IME'si bunu yok sayıp yine de `input` olayı üretebiliyor.
2. **Regresyon testi yaz.** "abc" + boşluk gönderildiğinde uzağa **tam olarak
   `"abc "`** gitmeli, `"abcabc "` değil. Test saf fonksiyon üzerinde
   (`inputAction` zaten saf) çalışabilir — `onInput`'ın bileşiklik
   koruması da test edilebilir olmalı.
3. **Diğer bileşik tuşlar da kontrol edilsin:** nokta, virgül, rakamlar.
   Sadece boşlukta değil, **herhangi bir ayraçta** aynı çift gönderim var mı?
4. Sadece telefonda oluyorsa bunu da not et — masaüstünde `keydown` +
   `preventDefault` yolu çalıştığı için sorun görünmüyor olabilir.

## Kapsam notu

Bu, cihazdaki tek doğrulanamayan risk (Gboard noktalama koyarken gizli
boşluğu silerse uzakta fazladan karakter silinebilir — `docs/ACIK-KONULAR.md`
#15) ile aynı kökten. İkisi birlikte çözülürse iyi olur.

## Kalite kapısı

Derleme, vet, lint, testler temiz. Güvenlik denetimi. Push yapma.
