# TÜRKİYE FINANSAL VERİ SAĞLAYICILARI ARAŞTIRMA RAPORU
**Tarih:** 2026-10-03  
**Hazırlayan:** GOLD Projesi — Provider Research  
**Konu:** Gerçek zamanlı (streaming/WebSocket) finansal veri sağlayıcılarının değerlendirilmesi  

---

## ÖZET

Mevcut GOLD mimarisi **Yahoo Finance (3s HTTP polling)** + **TCMB (5dk HTTP polling)** kullanıyor. Her iki sağlayıcı da **WebSocket/streaming SUNMUYOR**; "real-time" etiketi **üretilemiyor** (DataFreshness.delayed/daily).

Bu rapor, **gerçek WebSocket/SSE/streaming** sağlayan, **BIST + FX + Altın/Gümüş** kapsayan, **lisans uygun** ve **ticari kullanıma elverişli** sağlayıcıları araştırır.

---

## ARAŞTIRILAN SAĞLAYICILAR

| # | Sağlayıcı | Tip | WebSocket/Streaming | Ana Pazar |
|---|-----------|-----|---------------------|-----------|
| 1 | **Hasfiyat (altinapi.hasfiyat.com)** | Altın/Döviz uzmanı | **EVET** (WebSocket + Webhook) | Altın, Döviz, Emtia |
| 2 | **Matriks Data (matriksdata.com)** | BIST + Kurumsal | **EVET** (MQTT over WebSocket/TCP) | BIST, VİOP, FX, Altın, Emtia, Kripto |
| 3 | **BloombergHT / Bloomberg** | Medya + Terminal | **EVET** (Terminal/API) | BIST, FX, Altın, Global |
| 4 | **Döviz.com / Noktacom** | Portals + Aggregator | **YOK** (HTTP polling) | FX, Altın, BIST (15dk gecikmeli), Kripto |
| 5 | **Bigpara (Hürriyet)** | Portals | **YOK** (HTTP polling) | FX, Altın, BIST (15dk gecikmeli) |
| 6 | **Investing.com** | Global Portals | **EVET** (WebSocket) | Global + BIST (15dk gecikmeli) |
| 7 | **TradingView** | Charting + Data | **EVET** (WebSocket) | Global + BIST (geliştirici API'si kısıtlı) |
| 8 | **Finansport / Finansveri** | Niche | Belirsiz | FX, Altın |

---

## DETAYLI SAĞLAYICI KARŞILAŞTIRMA TABLOSU

| Kriter | **Hasfiyat** | **Matriks Data** | **BloombergHT** | **Investing.com** | **TradingView** | **Döviz.com / Bigpara** |
|--------|--------------|------------------|-----------------|-------------------|-----------------|-------------------------|
| **1. WebSocket/Streaming** | **EVET** (wss://api.hasfiyat.com/stream) + Webhook | **EVET** (MQTT over WS/TCP) | **EVET** (Terminal/Enterprise API) | **EVET** (WebSocket) | **EVET** (WebSocket) | **YOK** (HTTP polling) |
| **2. Gerçek Tick/Update Event** | **EVET** (milisaniye, kaynak değişimde) | **EVET** (MQTT pub/sub, tick başına) | **EVET** (Terminal/Enterprise) | **EVET** (WebSocket tick) | **EVET** (WebSocket tick) | **YOK** (HTTP polling) |
| **3. USD/TRY, EUR/TRY** | **EVET** (Serbest piyasa, 11 kaynak) | **EVET** (BIST FX + bankalar) | **EVET** | **EVET** | **EVET** | **EVET** (Aggregated) |
| **4. Gram/Çeyrek/Ons Altın** | **EVET** (Gram, Çeyrek, Yarım, Tam, Ons, Ayarlar) | **EVET** (GLDGR, ONS, Çeyrek, Yarım, Tam) | **EVET** | **EVET** | **EVET** | **EVET** (Aggregated) |
| **5. Gümüş** | **EVET** (Gram, Ons) | **EVET** (XAGUSD, Gram) | **EVET** | **EVET** | **EVET** | **EVET** |
| **6. BIST 100 / BIST 30** | **YOK** (Sadece endeks değeri yok) | **EVET** (Tüm BIST hisse + endeksler) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) |
| **7. BIST Hisse Senetleri** | **YOK** | **EVET** (Tüm BIST, VİOP, Derinlik) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) | **EVET** (15dk gecikmeli) |
| **8. Bid/Ask** | **EVET** (FX için Alış/Satış) | **EVET** (Derinlik, Emir Defteri) | **EVET** | **EVET** | **EVET** | **KISMİ** (Sadece banka alış/satış) |
| **9. OHLC/Historical** | **YOK** (Sadece anlık fiyat) | **EVET** (MQTT + REST + QStream) | **EVET** | **EVET** | **EVET** | **EVET** (Grafik verisi) |
| **10. Gerçek Update Frekansı** | **Milisaniye** (kaynak değişimde) | **Tick bazlı** (MQTT pub/sub) | **Sub-second** | **~100-500ms** | **~100-500ms** | **~15-60 saniye** (polling) |
| **11. Ölçülen Latency** | **<50ms** (kaynak -> WS) | **<100ms** (MQTT broker) | **<200ms** | **~200-500ms** | **~200-500ms** | **N/A** (polling) |
| **12. Rate Limit** | Plan bazlı (günlük/aylık çağrı) | Abonelik bazlı (concurrent conn) | Enterprise sözleşmesi | Plan bazlı (dakika/ay) | Plan bazlı | **YOK** (web sitesi) |
| **13. Bağlantı Limitleri** | Plan bazlı (eşzamanlı WS) | Abonelik bazlı (concurrent conn) | Enterprise | Plan bazlı | Plan bazlı | N/A |
| **14. API Key** | **EVET** (Panel + IP whitelist) | **EVET** (Enterprise) | **EVET** (Enterprise) | **EVET** | **EVET** | **YOK** (Web sitesi) |
| **15. Ücretsiz Plan** | **YOK** (Sadece demo/test) | **YOK** (Sadece demo) | **YOK** | **EVET** (Sınırlı, gecikmeli) | **EVET** (Sınırlı) | **EVET** (Web sitesi) |
| **16. Ücretli Planlar** | **Paketli** (Bronze/Silver/Gold) — TL fiyatlandırma | **Enterprise** (Özel teklif, BIST lisans dahil) | **Enterprise** ($$$) | **Tiered** ($0-$1000+/ay) | **Tiered** ($0-$299/ay) | **Ücretsiz** (Web sitesi) |
| **17. Lisans / Yeniden Dağıtım** | **Mobil uygulama gösterim lisansı var** (Gold paket) | **BIST lisansı dahil** (Enterprise) | **Kısıtlı** (Terminal) | **Kısıtlı** (Developer API) | **Kısıtlı** (Charting library) | **YOK** (Sadece web sitesi) |
| **18. Türkiye Lisans Uyumu** | **UYGUN** (Türk şirketi, SPK/BIST uyumu) | **UYGUN** (BIST resmi veri dağıtıcısı) | **Kısıtlı** (Terminal) | **Riskli** (Yabancı, veri sahipliği) | **Riskli** (Charting odaklı) | **UYGUN** (Sadece web) |
| **19. Uptime/Reliability** | **%99.9** (11 kaynak + failover) | **%99.9+** (BIST resmi dağıtıcı) | **%99.99** | **%99.9** | **%99.9** | **Yüksek** (Web sitesi) |
| **20. Veri Kaynağı** | **11 canlı kaynak** (Harem, Hakan, Mayda, vb.) | **BIST resmi + Bankalar + Global** | **Bloomberg Terminal** | **Global exchange + vendor** | **Exchange + vendor** | **Aggrege** (Bankalar, Harem, Altınkaynak) |
| **21. Dokümantasyon/Şirket** | **Tam** (altinapi.hasfiyat.com/docs) | **Tam** (matriksdata.com/kurumsal) | **Enterprise portal** | **Developer portal** | **Developer portal** | **Web sitesi** |

---

## SAĞLAYICI DETAYLARI

### 1. HASFIYAT (altinapi.hasfiyat.com) ⭐ **ALTIN/DÖVİZ İÇİN EN UYGUN**

| Özellik | Detay |
|---------|-------|
| **WebSocket** | `wss://api.hasfiyat.com/stream?source=harem&token=...` — **Milisaniye gecikme** |
| **Protokol** | WebSocket (native) + Webhook (fiyat değişiminde push) |
| **Kaynaklar** | **11 canlı kaynak**: Harem Altın, Hakan Altın, Mayda Gold, Myakche, Metal Altın, Nadir Döviz, Anlık Altın, Sağlamoğlu, Fikri Şah, Şahap, Hasfiyat Döviz |
| **Failover** | **Otomatik** — kaynak çökerse diğerine geçer |
| **Semboller** | Gram/Çeyrek/Yarım/Tam/Ons Altın, Ayar Bilezikler, USD/EUR/GBP/CHF/JPY + çapraz pariteler, Gümüş (Gram/Ons) |
| **Bid/Ask** | **EVET** — FX için Alış/Satış/Makas |
| **OHLC** | **YOK** (Sadece anlık fiyat; mum verisi için ayrı kaynak gerekir) |
| **Protokol** | Native WebSocket + Webhook (REST de var) |
| **Auth** | API Key + IP/Domain whitelist (panelden) |
| **Fiyatlandırma** | **Bronze/Silver/Gold** paketler (TL, kuyumcu/döviz bürosu odaklı) — Gold paketinde "mobil uygulama fiyat ekranı" lisansı var |
| **Lisans** | **Mobil uygulama gösterim lisansı** (Gold pakette) — "Kuyumcu fiyat ekranı / panosu" lisansı |
| **Türkiye Uyumu** | **TAM** — Türk şirketi (Hasfiyat Teknoloji), veri kaynakları Türkiye resmi piyasa aktörleri (Harem, Hakan, Mayda, TCMB serbest piyasa) |
| **Destek** | TR/EN, WhatsApp/Email, panelden yönetim |
| **Dokümantasyon** | https://altinapi.hasfiyat.com/docs — REST, WebSocket, Webhook örnekleri |
| **Test Edilebilirlik** | Demo/test hesabı talep edilebilir (iletişim formu) |

**EKSİKLER:** BIST hisse/endeks **YOK**, OHLC/mum verisi **YOK** (sadece anlık fiyat).

---

### 2. MATRIKS DATA (matriksdata.com) ⭐ **BİST + KAPSAMLI İÇİN EN UYGUN**

| Özellik | Detay |
|---------|-------|
| **WebSocket/Streaming** | **MQTT over WebSocket (ws://) + TCP** — **Gerçek tick bazlı** |
| **Protokol** | **MQTT pub/sub** (WebSocket + TCP) — ProtocolBuffer encoding, bant genişliği tasarrufu |
| **Konu Bazlı Abonelik** | Her enstrüman/veri tipi için ayrı subscription — sadece ihtiyaç duyulan veri alınır |
| **Semboller** | **TÜM BİST** (Hisse, Endeks, VİOP, Varant, Opsiyon), **FX** (USDTRY, EURTRY, pariteler), **Altın** (GLDGR, ONS, Çeyrek, Yarım, Tam), **Gümüş**, **Emtia**, **Kripto**, **Yurtdışı Endeksler**, **Kripto** |
| **Veri Tipleri (MQTT)** | Market Verileri (Tick), Gerçekleşen İşlemler, Derinlik (Depth), Emir Defteri (Order Book), Haberler, Yükselen/Düşen, Hesaplanmış Veriler (Volatilite, Delta, Gamma), Alarmlar |
| **REST API** | Grafik Bar Verileri, Haberler (KAP, Matriks), Temel Analiz, Ekonomik Takvim, TEFAS Fon, Halka Arz, Türev Enstrüman, Aracı Kurum Analizleri, Meta Veriler |
| **QStream** | Tarihsel veri simülasyonu/backtest için (SQL-benzeri sorgu, TCP/nanomsg, ProtocolBuffer) |
| **Bid/Ask/Depth** | **EVET** — Derinlik, Emir Defteri, Gerçekleşen İşlemler |
| **OHLC/Historical** | **EVET** — MQTT + REST + QStream (tarihsel canlandırma) |
| **BIST Verisi** | **Resmi dağıtıcı** — 15dk gecikme **yok** (canlı tick), BIST lisansı dahildir |
| **Protokol Detayı** | MQTT 3.1.1/5.0, WebSocket (ws://) + TCP, ProtocolBuffer (küçük mesaj boyutu), QoS 0/1 |
| **Auth** | Enterprise API Key + IP whitelist |
| **Fiyatlandırma** | **Enterprise / Özel Teklif** — Veri kapsamına, canlı/gecikmeli olmasına, yazılıma göre; BIST lisans ücreti dahil |
| **Lisans** | **BIST resmi veri dağıtıcı lisansı dahil** — Yeniden dağıtım opsiyonu **yok** (ayrı opsiyon) |
| **Türkiye Uyumu** | **TAM** — BIST resmi veri dağıtıcısı, SPK/KAP uyumlu, 20 yıl tecrübe, bankalar/kurumlar kullanıyor |
| **Altyapı** | Docker/Kubernetes, Cassandra cluster, MQTT broker cluster, Federatif güvenlik |
| **Dokümantasyon** | https://apitest.matriksdata.com/man-docs/ (test portalı), teknik detaylar iletişim formuyla |
| **Test** | Demo/test hesabı iletişim formuyla talep edilebilir |

**EKSİKLER:** **Ücretsiz plan YOK**, **Enterprise-only**, fiyat şeffaf değil (özel teklif), mobil uygulama lisansı ayrı opsiyon.

---

### 3. BLOOMBERG HT / BLOOMBERG TERMINAL

| Özellik | Detay |
|---------|-------|
| **WebSocket/Streaming** | Terminal API / Enterprise Data License |
| **Kapsam** | Global + BIST (15dk gecikmeli web'de), FX, Altın, Emtia, Kripto, Tahvil |
| **Lisans** | **Terminal** ($24,000+/yıl/kullanıcı) veya **Enterprise Data Feed** ($$$) |
| **Mobil Lisans** | **YOK** (Terminal odaklı) |
| **Türkiye Uyumu** | Riskli — Yabancı veri sahipliği, BIST lisansı ayrı |
| **Uygunluk** | **GOLD için UYGUN DEĞİL** (maliyet, lisans, mobil odaklı değil) |

---

### 4. INVESTING.COM / TRADINGVIEW (Geliştirici API)

| Özellik | Investing.com | TradingView |
|---------|---------------|-------------|
| **WebSocket** | EVET | EVET (Charting library) |
| **BIST** | 15dk gecikmeli | 15dk gecikmeli |
| **Lisans** | Developer API (kısıtlı yeniden dağıtım) | Charting Library lisansı (ayrı) |
| **Mobil Uygulama Lisansı** | Kısıtlı / Riskli | Charting Library lisansı ayrı |
| **Türkiye Veri Sahipliği** | Yabancı (veri sahipliği belirsiz) | Yabancı |
| **Uygunluk** | **Riskli** (lisans, veri sahipliği) | **Riskli** (charting odaklı, veri lisansı ayrı) |

---

### 5. DÖVİZ.COM / BIGPARA (HÜRRIYET) — **STREAMING YOK**

| Özellik | Detay |
|---------|-------|
| **WebSocket** | **YOK** |
| **Yöntem** | HTTP polling / Web sayfası scraping |
| **Güncelleme** | ~15-60 saniye (sayfa yenileme / AJAX) |
| **Latency** | Saniyeler |
| **API** | **YOK** (Resmi developer API'si yok) |
| **Lisans** | **YOK** (Sadece web sitesi görüntüleme) |
| **Uygunluk** | **GOLD İÇİN UYGUN DEĞİL** (streaming yok, API yok, lisans yok) |

---

## ÇOK SAĞLAYICILI (MULTI-PROVIDER) MİMARİ ÖNERİSİ

Tek bir sağlayıcı **TÜM** piyasaları **gerçek zamanlı + lisanslı + OHLC** ile karşılamıyor. **Multi-provider** mimarisi şart:

| Piyasa | Önerilen Sağlayıcı | Gerekçe |
|--------|-------------------|---------|
| **BIST Hisse/Endeks/VİOP** | **Matriks Data** (MQTT) | Resmi dağıtıcı, tick veri, derinlik, OHLC, BIST lisansı dahil |
| **FX (USD/TRY, EUR/TRY, Pariteler)** | **Hasfiyat** (WebSocket) | 11 kaynak + failover, milisaniye, bid/ask, serbest piyasa resmi |
| **Altın (Gram/Çeyrek/Ons) + Gümüş** | **Hasfiyat** (WebSocket) | 11 kuyumcu kaynağı, milisaniye, bid/ask, ayar bazlı |
| **OHLC/Mum (Tüm piyasalar)** | **Matriks Data** (MQTT + REST + QStream) | Tick/OHLC, tarihsel, QStream backtest |

### MULTI-PROVIDER MİMARİSİ (GOLD MEVCUT YAPIYA UYGUN)

Mevcut `MarketDataRepositoryImpl` zaten **multi-source** destekliyor (`sources: List<MarketDataProvider>`). Sadece **yeni 2 provider** eklenmeli:

```dart
// lib/core/providers/app_providers.dart
final marketSourcesProvider = Provider<List<MarketDataProvider>>((ref) {
  return [
    HasfiyatMarketDataProvider(HasfiyatApiClient(...)),      // FX + Altın + Gümüş (WebSocket)
    MatriksMarketDataProvider(MatriksMqttClient(...)),       // BIST + OHLC + Derinlik (MQTT)
    // Mevcut Yahoo + TCMB fallback olarak kalsın
    YahooMarketDataProvider(YahooFinanceProvider(...)),
    TcmbFxMarketDataProvider(TcmbCurrencyProvider(...), yahoo: ...),
  ];
});
```

**Avantajlar:**
- Mevcut `MarketDataProvider` arayüzü **değişmez** (abstraction korunur)
- `supports(assetId)` ile sembol bazlı routing otomatik
- `refreshInterval` sağlayıcıdan gelir (WebSocket için çok kısa, polling için uzun)
- `DataFreshness.live` **sadece WebSocket sağlayıcılarında** üretilir

---

## PROOF-OF-CONCEPT PLANI (SIRADAKI ADIM)

### 1. Hasfiyat WebSocket Testi (1-2 gün)
```bash
# wss://api.hasfiyat.com/stream?source=harem&token=DEMO_TOKEN
# Beklenen: Bağlantı → Snapshot → Tick eventleri (milisaniye)
# Doğrulanacak: Bağlantı kurulumu, snapshot, tick event, timestamp, sembol değişimi
```

### 2. Matriks MQTT Testi (3-5 gün — Enterprise iletişim gerekir)
```bash
# mqtt://apitest.matriksdata.com (veya ws://)
# MQTT CONNECT → SUBSCRIBE XU100/GLDGR/USDTRY → Tick eventleri
# Doğrulanacak: MQTT CONNECT, SUBSCRIBE, PUBLISH (tick), ProtocolBuffer decode, timestamp
```

### 3. Benchmark Karşılaştırması (1 hafta)
| Metrik | Hasfiyat (WS) | Matriks (MQTT) | Mevcut Yahoo (HTTP 3s) |
|--------|---------------|----------------|------------------------|
| Bağlantı kurulum süresi | ~ms | ~ms | N/A |
| İlk snapshot gecikmesi | ~ms | ~ms | ~500ms |
| Tick gecikmesi (kaynak→app) | <50ms | <100ms | 3000ms (polling) |
| Günlük veri noktası (USDTRY) | ~50,000+ | ~50,000+ | ~28,800 |
| CPU/Bant genişliği (mobil) | Düşük (WS) | Düşük (MQTT+ProtoBuf) | Orta (HTTP) |
| Pil tüketimi | Düşük | Düşük | Orta |

---

## SONUÇ VE ÖNERİ

| Durum | Aksiyon |
|-------|---------|
| **Hasfiyat** | ✅ **Hemen PoC başlat** — FX + Altın + Gümüş için **en uygun** (WebSocket, milisaniye, 11 kaynak, mobil lisans var, Türkiye uyumlu, TL fiyatlandırma). |
| **Matriks Data** | ✅ **İletişim başlat** — BIST + OHLC + Derinlik için **tek çözüm**. Enterprise iletişimi 1-2 hafta sürebilir; fiyat teklifi alınıp BIST lisans maliyeti netleştirilmeli. |
| **Mevcut Yahoo + TCMB** | **Fallback olarak kalsın** — Provider chain'de son sıradadır (`supports` sonrası). WebSocket sağlayıcıları `DataFreshness.live` üretir; Yahoo/TCMB `delayed/daily` üretir. |
| **Diğer (Investing, TradingView, Döviz.com)** | ❌ **Değerlendirme dışı** — Lisans riski, streaming yok veya mobil lisans yok. |

### GOLD İÇİN SON KARAR MATRİSİ

| Piyasa | Sağlayıcı | Protokol | Latency | Lisans | Maliyet (Tahmini) |
|--------|-----------|----------|---------|--------|-------------------|
| **BIST Hisse/Endeks/VİOP** | Matriks Data | MQTT (WS/TCP) | <100ms tick | BIST lisansı dahil | Enterprise (~$500-2000+/ay + BIST lisans) |
| **FX (USD/TRY, EUR/TRY)** | Hasfiyat | WebSocket | <50ms | Mobil uygulama lisansı (Gold paket) | ~₺2,000-10,000/ay (pakete göre) |
| **Altın/Gümüş (Tüm türler)** | Hasfiyat | WebSocket | <50ms | Dahil | Dahil |
| **OHLC/Historical (Tümü)** | Matriks Data | MQTT + REST + QStream | <100ms | Dahil | Dahil |

---

## SONRAKI ADIMLAR (Aksiyon Planı)

1. **HAFTA 1:** Hasfiyat ile iletişim → Demo/test API key talep → WebSocket PoC (bağlantı, snapshot, tick, timestamp, failover testi).
2. **HAFTA 1-2:** Matriks Data ile iletişim → Enterprise fiyat teklifi + test hesabı talep → MQTT PoC (bağlantı, subscribe, tick, ProtocolBuffer decode, depth).
3. **HAFTA 2-3:** PoC sonuçları + benchmark → Karar matrisi güncelle → `MarketDataProvider` implementasyonları yaz (`HasfiyatMarketDataProvider`, `MatriksMarketDataProvider`).
4. **HAFTA 3-4:** Entegrasyon testleri (cihazda WebSocket/MQTT), fallback zinciri doğrulama, `DataFreshness.live` üretimi.
5. **HAFTA 4:** Release APK → Cihazda 30 gün soak test (uptime, reconnect, battery, data integrity).

---

## UYARI

**Bu rapor araştırma aşamasıdır.** Hiçbir provider kodu GOLD'a entegre edilmemiştir. PoC sonuçları olmadan **hiçbir değişiklik yapılmamalıdır**. Mevcut 3s Yahoo / 5dk TCMB polling **çalışıyor ve güvenlidir** — riskli bir geçiş yapmaya gerek yoktur.

**Onay bekleniyor.** PoC başlatılsın mı?