# AuTR WebSocket PoC - Kullanım Kılavuzu

## Amaç
Autr.tr WebSocket API'sinin **gerçek zamanlı** (sub-second) FX + Altın + Çeyrek Altın + Gümüş veri akışını doğrulamak.

**Resmi Dokümantasyon:**
- API: https://autr.tr/sayfa/atr-doviz-kuru-api-dokumantasyonu
- WebSocket: https://autr.tr/api-servisi/websocket-canli-kur-servisi
- Canlı REST: https://autr.tr/api-servisi/live-exchange-rates-rest-api-json

## Resmi Endpoint Bilgileri

| Bileşen | Değer |
|---------|-------|
| REST Endpoint | `https://autr.tr/api/prices/live` |
| WebSocket | `wss://autr.tr/ws/prices?api_key=ak_live_...` |
| Auth Format | `ak_live_...` (URL query param veya `X-API-Key` header) |
| WS Init | `{"type": "init", "snapshot": [...]}` |
| WS Updates | `[[idx, alis, satis], ...]` (index-based) |
| Rate Limit | 60 istek/dk (ücretsiz) |
| WS Latency Claim | < 20ms |

## Semboller (Test Edilecek)

| Sembol | Açıklama |
|--------|----------|
| USDTRY | USD/TRY |
| EURTRY | EUR/TRY |
| GRAMALTIN | Gram Altın |
| CEYREK_YENI | Çeyrek Altın Yeni |
| GUMUSTRY | Gümüş TL |

## Kurulum

```bash
# 1. Bağımlılıklar
pip install websockets aiohttp python-dotenv

# 2. .env.example kopyala
cp .env.example .env

# 3. .env içine API key ekle
# AUTR_API_KEY=ak_live_... (https://autr.tr/user/api-key)

# 4. Çalıştır
python autr_poc.py
```

## API Key Alma
1. https://autr.tr/register → Hesap oluştur
2. Dashboard → https://autr.tr/user/api-key → "API Anahtarı Oluştur"
3. Key formatı: `ak_live_...` (doküman tekrarlıyor)

## Çalıştırma
```bash
cd tools/autr_poc
pip install -r requirements.txt
python autr_poc.py
```

## Test Edilenler
1. REST Snapshot (`GET https://autr.tr/api/prices/live` + `X-API-Key`)
2. WebSocket bağlantısı (`wss://autr.tr/ws/prices?api_key=...`)
3. Init snapshot (`{"type": "init", "snapshot": [...]}`)
4. Index-based updates (`[[idx, alis, satis], ...]`)
5. 60 saniye event loglama
6. Reconnect testi

## Ölçülen Metrikler
- Sembol başına update interval: min/median/avg/max (ms)
- Duplicate event oranı
- Snapshot alma süresi
- Reconnect sayısı
- Authentication hatası

## Çıktı Formatı
Her event için:
```
[WS]  📊 USDTRY: alis=49.1100, satis=49.1750
```

Sonuçta:
- Event interval istatistikleri (min/median/avg/max)
- Duplicate oranı
- Yahoo 3s polling ile karşılaştırma
- Verdict: PASS/FAIL/PARTIAL