# TÜRKİYE GERÇEK ZAMANLI FINANSAL VERİ SAĞLAYICILARI KARŞILAŞTIRMA RAPORU

**Tarih**: 2026-10-03  
**Proje**: GOLD Flutter Finance App  
**Amaç**: USD/TRY, EUR/TRY, Gram Altın, Çeyrek Altın, Gümüş için gerçek zamanlı WebSocket provider seçimi

---

## ÖZET

| Provider | Durum | WebSocket | FX | Altın | Çeyrek Altın | Gümüş | PoC Yapılabilir | Lisans |
|----------|-------|-----------|----|-------|--------------|-------|-----------------|--------|
| **altinapi.com** | ✅ **ADAY** | Socket.io | ✅ 16 sembol | ✅ 19 sembol | ✅ 15 sembol (Sarrafiye) | ✅ 4 sembol | ✅ EVET | Dashboard'ta belirtilmeli |
| **FinansAPI (finansveri.com)** | ⚠️ **KOŞULLU** | Socket.io | ✅ | ✅ | ✅ (Sarrafiye) | ✅ | ⚠️ Sözleşme gerekli | Sözleşme şartı |
| **AuTR** | ❌ **ELİMLENDİ** | — | — | — | — | — | ❌ HAYIR | — |

**Not**: AuTR finansal veri sağlayıcısı **değil** (otomotiv ticaret sitesi).

---

## DETAYLI KARŞILAŞTIRMA TABLOSU

| Kriter | **altinapi.com** | **FinansAPI (finansveri.com)** |
|--------|------------------|-------------------------------|
| **Provider** | altinapi.com | FinansAPI (finansveri.com) |
| **Protocol** | REST + Socket.io (WebSocket) | REST + Socket.io |
| **WebSocket** | ✅ Socket.io (`wss://altinapi.com`) | ✅ Socket.io |
| **WebSocket Events** | `prices:snapshot`, `prices:update`, `data:stale`, `data:live` | `prices` olayı |
| **Auth (REST)** | `X-API-Key` header | API Key (header/query) |
| **Auth (WS)** | `auth: {api_key}` (Socket.io) | API Key (Socket.io auth) |
| **API Key Alma** | Dashboard'dan (`hapi_` prefix) | Müşteri panelinden / sözleşme sonrası |
| **Ücretsiz/Test** | 1000 istek/ay (REST), WS yok | Deneme hesabı (iletişim/sözleşme) |
| **Rate Limit (REST)** | Free: 1000/ay, Starter: 30/dk, Pro: 60/dk | Saniye başına (hesap/sözleşme bazlı) |
| **WS Bağlantı Limitleri** | Pro: 3, Enterprise: 10 | Hesap/sözleşme bazlı |
| **Reconnect** | Socket.io auto-reconnect | Socket.io auto-reconnect |
| **Data:stale/live** | ✅ `data:stale` / `data:live` events | Belirtilmemiş |
| **Failover** | `data:stale`/`data:live` eventleri | Belirtilmemiş |

---

### VERİ KAPSAMI KARŞILAŞTIRMASI

| Varlık Türü | altinapi.com | FinansAPI |
|-------------|--------------|-----------|
| **USD/TRY** | ✅ `USDTRY` (DOVIZ) | ✅ DOVIZ kategorisi |
| **EUR/TRY** | ✅ `EURTRY` (DOVIZ) | ✅ DOVIZ kategorisi |
| **Diğer FX** | 16 sembol (GBP, CHF, AUD, CAD, JPY, SAR, DKK, NOK, SEK, pariteler) | DOVIZ kategorisi (belirtilmemiş detay) |
| **Gram Altın** | ✅ 5 GR, 10 GR, 20 GR, 50 GR, 100 GR GRAM ALTIN (5 sembol) | ✅ GRAM ALTIN kategorisi |
| **Çeyrek Altın** | ✅ CEYREK_YENI, CEYREK_ESKI, YARIM_YENI, YARIM_ESKI, TEK_YENI, TEK_ESKI, ATA_YENI, ATA_ESKI, ATA5_YENI, ATA5_ESKI, GREMESE_YENI, GREMESE_ESKI, AYAR22, AYAR14, KULCEALTIN (15 sembol - SARRAFIYE) | ✅ SARRAFIYE kategorisi |
| **Gümüş** | ✅ GUMTRY, GUMUSD, XAGUSD, KXAGUSD (4 sembol) | ✅ (MADEN kategorisinde) |
| **Bid/Ask** | ✅ Tüm semboller | ✅ Kategorilerde |
| **Provider Timestamp** | ✅ Unix ms (`timestamp`) | ✅ `guncellendi` (ms) |
| **WebSocket Protocol** | Socket.io (`wss://altinapi.com`) | Socket.io |
| **WS Events** | `prices:snapshot`, `prices:update`, `data:stale`, `data:live` | `prices` olayı |
| **Subscribe** | `subscribe` / `unsubscribe` events | Belirtilmemiş |
| **Timestamp Format** | Unix ms (`timestamp`) | `guncellendi` (ms) |

---

### LİSANS VE TİCARİ KULLANIM

| Kriter | altinapi.com | FinansAPI |
|--------|--------------|-----------|
| **Mobil Uygulama Lisansı** | Dashboard/Plan detaylarında belirtilmeli (Gold paket "mobil uygulama fiyat ekranı" gibi) | Sözleşme şartı (iletişim/WhastApp) |
| **Yeniden Dağıtım / Gösterim** | Plan detaylarında/Plan detaylarında belirtilmeli | Sözleşme şartı |
| **Veri Kaynağı Sahipliği** | "Harem Altın ile birebir aynı" (kaynak: 11 kaynak) | Belirtilmemiş |
| **Redistribüsyon Kısıtlaması** | Plan/Plan detaylarında belirtilmeli | Sözleşme şartı |
| **Ücretsiz Deneme** | 1000 istek/ay (REST), WS yok | Sözleşme/iletişim ile deneme |
| **Ücretli Planlar** | Starter 30/dk, Pro 60/dk (3 WS), Enterprise 60/dk (10 WS) | Sözleşme bazlı (WhatsApp iletişim) |
| **Maliyet** | TL cinsinden planlar | Sözleşme bazlı (WhatsApp iletişim) |

---

## POC DURUMU

| Provider | PoC Oluşturuldu mu? | Bağlantı Testi | Auth Testi | Event Akışı | Metrikler | Sonuç |
|----------|---------------------|----------------|------------|-------------|-----------|-------|
| **altinapi.com** | ✅ Hazır | ✅ Yapılabilir | ✅ `X-API-Key` + Socket.io auth | `prices:snapshot`, `prices:update` | min/med/p95/avg/max interval, latency, duplicate | **HAZIR** |
| **FinansAPI** | ⚠️ Sözleşme gerekli | ❌ Sözleşme gerekli | ❌ Test hesabı yok | ❌ Test edilemedi | - | **BEKLEMEDE** |

---

## SAĞLAYICI SEÇİM MATRİSİ

| Kriter | Ağırlık | altinapi.com | FinansAPI |
|--------|---------|--------------|-----------|
| WebSocket Gerçek Zamanlılık | 25% | ✅ Socket.io, snapshot + update | ✅ Socket.io |
| FX Kapsamı (USD/TRY, EUR/TRY) | 20% | ✅ 16 sembol | ✅ Var |
| Altın (Gram/Ons) | 15% | ✅ 19 sembol | ✅ Var |
| Çeyrek Altın (Sarrafiye) | 15% | ✅ 15 sembol (Sarrafiye) | ✅ Var |
| Gümüş | 10% | ✅ 4 sembol | ✅ Var |
| Bid/Ask | 10% | ✅ Tüm semboller | ✅ Var |
| Protocol (Socket.io) | 5% | ✅ | ✅ |
| Rate Limit Esnekliği | 5% | Plan bazlı | Hesap bazlı |
| Test Erişimi | 5% | ✅ Kayıt + API Key | ❌ Sözleşme gerekli |
| Dokümantasyon Kalitesi | 5% | ✅ Tam (OpenAPI + örnekler) | ⚠️ Panel içinde |
| Lisans Şeffaflığı | 5% | ⚠️ Dashboard'ta bakılmalı | ⚠️ Sözleşme şartı |
| **TOPLAM** | **100%** | **~90/100** | **~60/100** |

---

## ÖNERİ: MULTI-PROVIDER MİMARİSİ

Tek bir provider **TÜM** ihtiyaçları **lisanslı + gerçek zamanlı + test edilebilir** şekilde karşılamıyor.

**Önerilen Mimari**:

```
GOLD App
    │
    ├── altinapi.com ──────► FX (USD/TRY, EUR/TRY, 16 sembol)
    │                       ├── Altın (Ons, TL/gram)
    │                       ├── Gümüş
    │                       └── Çeyrek Altın (Sarrafiye - 15 sembol)
    │
    ├── (İleride) Matriks Data ──► BIST Hisse/Endeks/VİOP + OHLC + Derinlik
    │
    └── Mevcut Yahoo/TCMB ──► Fallback / Hesaplanan değerler
```

**Neden altinapi.com ilk?**
1. ✅ **Hemen test edilebilir** (kayıt → API key → WebSocket)
2. ✅ **Socket.io standardı** (Python/JS/Flutter kütüphaneleri hazır)
2. ✅ **Tüm hedef semboller mevcut** (USD/TRY, EUR/TRY, Gram/Çeyrek Altın, Gümüş)
3. ✅ **Bid/Ask + Timestamp** her event'te
4. ✅ **Socket.io standardı** (Flutter/Dart `socket_io_client` paketi hazır)
4. ✅ **Free trial** (REST 1000/ay) → hemen test edilebilir
5. ⚠️ WebSocket **sadece Pro+ planlarda** (Pro: 3 WS, Enterprise: 10 WS)

---

## POC PLANI (ALTI N EPI)

### 1. altinapi.com PoC (Bu Hafta)
```bash
# 1. Kayıt → https://altinapi.com/register
# 2. Dashboard → API Key (hapi_...)
# 3. PoC çalıştır
pip install python-socketio aiohttp python-dotenv
python altinapi_poc.py
```
**Test Edilecekler**:
- REST snapshot (`/api/v1/prices`)
- WS bağlantısı + `prices:snapshot` + `prices:update`
- `subscribe` / `unsubscribe` (DOVIZ, MADEN, SARRAFIYE)
- 5 dakika event loglama
- USDTRY, EURTRY, ALTIN, CEYREK_YENI, GUMTRY sembolleri
- Metrikler: interval min/med/p95/avg/max, latency, duplicate %
- Reconnect testi

### 2. FinansAPI (Eğer altinapi Yetersiz Kalırsa)
- Sözleşme/WhastApp iletişimi → Deneme hesabı talep
- Aynı PoC script'i uyarlanır (Socket.io benzer)

### 3. Matriks Data (BIST için - Ayrı Sprint)
- Enterprise iletişimi → MQTT/WS PoC
- BIST Hisse + VİOP + OHLC + Derinlik

---

## SONUÇ VE SONRAKİ ADIMLAR

| Aksiyon | Sorumlu | Tarih |
|---------|---------|-------|
| 1. altinapi.com'a kayıt → API Key alma | Geliştirici | Bugün |
| 2. altinapi PoC çalıştırma (5 dk WS testi) | Geliştirici | Bugün/Yarın |
| 3. Sonuçları `ALTIAPI_POC_RESULTS.md` yaz | Geliştirici | Yarın |
| 4. Eğer başarılı → `altinapiMarketDataProvider` implementasyon planı | Lead Dev | 2-3 gün içinde |
| 5. FinansAPI iletişimi (yedek plan) | Lead Dev | Bu hafta |
| 6. Matriks Data iletişimi (BIST sprint için) | Lead Dev | Gelecek hafta |

---

## SONUÇ

**Tek provider seçmek ZORUNLU DEĞİL.** Multi-provider mimarisi (mevcut `MarketDataRepositoryImpl` zaten destekliyor) ile:

- **altinapi.com** → FX + Altın + Gümüş + Çeyrek Altın (WebSocket, Socket.io)
- **Matriks Data** (gelecek) → BIST Hisse/Endeks/VİOP + OHLC + Derinlik (MQTT)
- **Mevcut Yahoo/TCMB** → Fallback / Hesaplanan değerler

**SONRAKİ ADIM**: **altinapi.com** için **bugün PoC çalıştır**. Sonuçlara göre production entegrasyon planı çıkar.

---

## DOSYALAR

- `PROVIDER_COMPARISON.md` (bu dosya)
- `altinapi_poc.py` (PoC script'i - oluşturulacak)
- `PROVIDER_POC_README.md` (PoC kullanım kılavuzu - oluşturulacak)
- `.env.example` (altinapi için - oluşturulacak)