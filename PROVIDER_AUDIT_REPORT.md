# KAYNAK DENETİM RAPORU — Kyron (GOLD) Gerçek Veri Akışı

**Tarih:** 2026-10-04  
**Amaç:** Her asset için çalışma anında hangi provider'ın quote ürettiğini kod akışından takip edip tablo vermek.

---

## YÖNTEM

Şunlar kod üzerinden takip edildi:

1. **AssetCatalog** asset ID ve `isCalculated` bayrağı
2. **Repository** `getQuotes`/`watchQuotes` akışı (`MarketDataRepositoryImpl`)
3. **Provider seçim/priority** mantığı (`_quoteSourceFor`, `marketSourcesProvider`)
4. Her provider'ın `supports()` mantığı
5. `_deriveAll()` koruma mantığı ve ne zaman tetiklendiği

Hiçbir dosya değiştirilmedi; sadece statik kod analizi yapıldı.

---

## PROVIDER ÖNCELİK SIRASI (app_providers.dart:70-82)

```dart
final marketSourcesProvider = Provider<List<MarketDataProvider>>((ref) {
  return [
    // 1. Döviz: fiyat/alış-satış TCMB (resmi), %değişim Yahoo paritesi.
    TcmbFxMarketDataProvider(tcmb, yahoo: yahoo),
    // 2. BIST + ons metal: dogrudan Yahoo.
    YahooMarketDataProvider(yahoo),
    // 3. Altın/Gümüş: Anlık Altın Fiyatları (canli ~60sn).
    anlik,
  ];
});
```

Repository'deki `_quoteSourceFor()` **ilk** destekleyen provider'ı döndürür.

---

## HER PROVIDER'IN DESTEK MATRİSİ

| Provider | Destek Şartı (supports) |
|----------|-------------------------|
| **TCMB** | `asset.category == doviz` && `!asset.isCalculated` |
| **Yahoo** | `!asset.isCalculated` && `asset.category != doviz` |
| **AnlıkAltınFiyatları** | `assetId ∈ _supportedDirect` (live endpointi olanlar) |

`AnlikAltinFiyatlariProvider._supportedDirect` şunları içerir:
`gramAltinId, ceyrekAltinId, yarimAltinId, cumhuriyetAltinId, bilezik22Id, ayar14AltinId, ayar18AltinId, resatAltinId, gramGumusId, onsGumusId`

---

## ASSET CATALOG SINIFLANDIRMASI

| Asset | Asset ID | isCalculated | Category | Yahoo Sembolü | Anlık Endpoint |
|-------|----------|--------------|----------|---------------|----------------|
| Gram Altın | gram-altin | **true** | altin | — | gramlive.json |
| Çeyrek Altın | ceyrek-altin | **true** | altin | — | ceyreklive.json |
| Yarım Altın | yarim-altin | **true** | altin | — | yarimlive.json |
| Cumhuriyet Altını | cumhuriyet-altin | **true** | altin | — | cumhuriyetlive.json |
| 22 Ayar | bilezik-22 | **true** | altin | — | 22ayarlive.json |
| 14 Ayar | 14-ayar-altin | **false** | altin | AYAR14 (yok) | 14ayarlive.json |
| 18 Ayar | 18-ayar-altin | **false** | altin | AYAR18 (yok) | 18ayarlive.json |
| Reşat | resat-altin | **false** | altin | RESAT (yok) | resatlive.json |
| Ons Altın | ons-altin | **false** | altin | **GC=F** | onaltinlive.json |
| Gram Gümüş | gram-gumus | **true** | gumus | — | gumuslive.json |
| Ons Gümüş | ons-gumus | **false** | gumus | **SI=F** | gumusonslive.json |
| USD/TRY | usd-try | **false** | doviz | USDTRY=X (sadece %) | usdtrylive.json (test edilmemiş) |
| EUR/TRY | eur-try | **false** | doviz | EURTRY=X (sadece %) | eurtrylive.json (test edilmemiş) |

---

## REPOSITORY AKİŞI (getQuotes)

1. **Cache** kontrolü
2. Eksikleri `directRequested` (`!isCalculated`) ve `derivedRequested` (`isCalculated`) olarak ayır
3. **Direct fetch**: `directRequested` için `_fetchDirect()` → her asset **tek bir** provider'a atanır (priority sırasıyla)
4. **Derive**: `derivedRequested` için ancestor'ları çek, sonra `_deriveAll()`
5. `_deriveAll()` içinde: `if (quotes.containsKey(id)) continue;` → **sadece zaten direct çekilmişse** korur

**KRİTİK SORUN:** `isCalculated: true` assetler (Gram, Çeyrek, Yarım, Cumhuriyet, 22 Ayar, Gram Gümüş) **asla** `directRequested` listesine girmezler. Doğrudan `_deriveAll()`'e giderler. Dolayısıyla AnlıkAltınFiyatları provider'ı bu assetler için **hiç çağrılmaz**.

---

## GERÇEK SONUÇ TABLOSU

| Asset | Gerçek Provider | Endpoint / Sembol | Fallback Provider | Direct / Calculated |
|-------|-----------------|-------------------|-------------------|---------------------|
| **Gram Altın** | **Yahoo (via derivation)** | GC=F (Ons Altın) × USD/TRY (TCMB) | TCMB (USD/TRY için) | **Calculated** |
| **Çeyrek Altın** | **Yahoo (via derivation)** | Gram Altın × 1.75 | — | **Calculated** |
| **Yarım Altın** | **Yahoo (via derivation)** | Gram Altın × 3.50 | — | **Calculated** |
| **Cumhuriyet Altını** | **Yahoo (via derivation)** | Gram Altın × 7.216 | — | **Calculated** |
| **22 Ayar** | **Yahoo (via derivation)** | Gram Altın × 0.916 | — | **Calculated** |
| **14 Ayar** | **Yahoo (başarısız — sembol yok)** | AYAR14 (Yahoo'da yok) | AnlıkAltınFiyatları (denenmez) | **Eksik / Stale Cache** |
| **18 Ayar** | **Yahoo (başarısız — sembol yok)** | AYAR18 (Yahoo'da yok) | AnlıkAltınFiyatları (denenmez) | **Eksik / Stale Cache** |
| **Reşat** | **Yahoo (başarısız — sembol yok)** | RESAT (Yahoo'da yok) | AnlıkAltınFiyatları (denenmez) | **Eksik / Stale Cache** |
| **Ons Altın** | **Yahoo** | **GC=F** (COMEX futures) | AnlıkAltınFiyatları (denenmez) | **Direct** |
| **Gram Gümüş** | **Yahoo (via derivation)** | SI=F (Ons Gümüş) × USD/TRY (TCMB) | TCMB (USD/TRY için) | **Calculated** |
| **Ons Gümüş** | **Yahoo** | **SI=F** (COMEX futures) | AnlıkAltınFiyatları (denenmez) | **Direct** |
| **USD/TRY** | **TCMB** | today.xml (resmi günlük kur) | Yahoo (sadece %değişim) | **Direct** |
| **EUR/TRY** | **TCMB** | today.xml (resmi günlük kur) | Yahoo (sadece %değişim) | **Direct** |

---

## ANA BULGULAR

### ❌ Gram Altın **AnlıkAltınFiyatları `gramlive` endpointinden GELMİYOR**

Ekranda görünen Gram Altın fiyatı: **Yahoo Finance `GC=F` (Ons Altın) × TCMB `USD/TRY` formülüyle hesaplanmış değer**.  
`source: QuoteSourceLabel.calculated` etiketiyle gelir. AnlıkAltınFiyatları provider'ın canlı `gramlive.json` endpointi **hiç çağrılmıyor**.

### ❌ Çeyrek / Yarım / Cumhuriyet / 22 Ayar da **Anlık'tan GELMİYOR**

Hepsi `isCalculated: true` olduğu için Gram Altın üzerinden hesaplanıyor (zincirleme derivation). AnlıkAltınFiyatları'nın `ceyreklive`, `yarimlive`, `cumhuriyetlive`, `22ayarlive` endpointleri **kullanılmıyor**.

### ❌ 14 Ayar / 18 Ayar / Reşat için **Yahoo denendi, başarısız, Anlık denenmedi**

Bu üç asset `isCalculated: false` olduğu için `directRequested` listesine girer.  
Yahoo `supports()` → `true` döndürür (calculated değil, doviz değil).  
Yahoo `fetchSymbol` → `AYAR14` / `AYAR18` / `RESAT` (bu semboller Yahoo'da **yok**).  
Yahoo `Success` döndürür ama bu assetler yanıtta **yok**.  
Repository `lastFailure == null` olduğu için **stale cache'e düşer** (varsa), yoksa asset **sonuçta yok**.  
AnlıkAltınFiyatları **asla denenmez** çünkü Yahoo zaten "destekliyor" (sadece veri getiremiyor).

### ✅ Ons Altın / Ons Gümüş → **Yahoo'dan DOĞRUDAN geliyor**

`isCalculated: false`, Yahoo `GC=F` / `SI=F` ile destekliyor. AnlıkAltınFiyatları'non `onaltinlive` / `gumusonslive` endpointleri **denenmez**.

### ✅ USD/TRY / EUR/TRY → **TCMB'den DOĞRUDAN geliyor**

`category == doviz`, TCMB ilk provider → kazanır. Fiyat `today.xml`'den, `%değişim` Yahoo paritesinden.

---

## NEDEN BÖYLE? (MİMARİ SEBEP)

`MarketDataRepositoryImpl.getQuotes()` (satır 179-187):

```dart
for (final id in missing) {
  final asset = AssetCatalog.byId(id);
  if (asset == null) continue;
  if (asset.isCalculated) {
    derivedRequested.add(id);      // ← Anlık provider'ı asla çağrılmaz
  } else {
    directRequested.add(id);       // ← Yahoo/TCMB atanır
  }
}
```

**`isCalculated` bayrağı AssetCatalog'ta derleme-zamanı sabiti.**  
Provider'ların yetenekleri (`supports()`) bu bölünmeden **sonra** kontrol edilir.  
Dolayısıyla "hesaplanıyor" diye işaretlenmiş bir asset için **hiçbir provider doğrudan fiyat getiremez** — repository zaten "bu hesaplanacak" demiş olur.

AnlıkAltınFiyatları provider'ı `_supportedDirect` içinde Gram/Çeyrek/... olsa bile, repository onları **hesaplanacak** sanıp doğrudan fetch etmez.

---

## DÜZELTME ÖNERİSİ (Kod Değiştirmeden Sadece Analiz)

Eğer AnlıkAltınFiyatları'nın canlı fiyatları kullanılmak isteniyorsa:

1. **AssetCatalog'da** `isCalculated: false` yapmak **yeterli değil** — o zaman Yahoo onları alır (ve Yahoo'da sembol yok).
2. **Provider priority'sini değiştirmek** (Anlık'ı Yahoo'dan önce koymak) — yeterli olurdu Çeyrek/14/18/Reşat/Ons için, AMA Gram/Gram Gümüş yine `isCalculated: true` olduğu için derivation'a giderdi.
3. **Doğru çözüm:** Repository'de `directRequested`/`derivedRequested` ayırımı **provider yeteneğine göre** yapılmalı, `isCalculated` bayrağına göre değil.  
   Veya `_deriveAll()`'e girmeden önce "bu asset için direct provider quote var mı?" kontrolü eklenmeli (mevcut `quotes.containsKey(id)` koruması zaten bunu yapıyor ama asset hiç `directRequested` olmaması için quote map'e girmiyor).

---

## SONUÇ

**GOLD/Kyron şu an AnlıkAltınFiyatları'nın doğrudan canlı fiyatlarını (Gram, Çeyrek, Yarım, Cumhuriyet, 22 Ayar, Gram Gümüş için) KULLANMIYOR.**

Tüm bu ana altın ürünleri **Yahoo Finance Ons fiyatı × TCMB kur formülüyle hesaplanıyor** (`source: calculated`).

AnlıkAltınFiyatları provider'ı **kaydedilmiş ama etkin değil** — sadece 14/18/Reşat/Ons Gümüş için "ikinci sıra" provider oluyor, ama Yahoo onları "destekliyor" (veri getirememesine rağmen) dediği için asla çağrılmıyor.

> **Kesin Cevap:** Gram Altın fiyatı **Yahoo Finance'tan (dolaylı derivation ile)** geliyor, **AnlıkAltınFiyatları `gramlive` endpointinden DEĞİL**.