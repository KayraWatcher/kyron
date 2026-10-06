# altinapi.com PoC - Kullanım Kılavuzu (Official Docs Compliant)

## Amaç
altinapi.com Socket.io WebSocket API'sinin **gerçek zamanlı** (sub-second) FX + Altın + Çeyrek Altın + Gümüş veri akışını doğrulamak.
**Resmi dokümantasyon**: https://altinapi.com/docs

## ⚠️ KRİTİK: Plan Gereksinimi
| Plan | REST | WebSocket |
|------|------|-----------|
| **Free Trial** | 1000 req/ay | ❌ **YOK** |
| **Starter** | 30/dk | ❌ **YOK** |
| **Pro** | 60/dk | ✅ **3 WS** |
| **Enterprise** | 60/dk | ✅ **10 WS** |

> **⚠️ KRİTİK**: WebSocket erişimi **sadece Pro+ planlarda** mevcuttur. Free trial ve Starter planlar **sadece REST** sunar.

## Gereksinimler
- Python 3.8+
- altinapi.com hesabı (https://altinapi.com/register)
- **Pro+ plan** (WebSocket için zorunlu)

## Kurulum

```bash
# 1. Bağımlılıkları yükle
pip install "python-socketio[client]" aiohttp python-dotenv

# 2. .env.example kopyalayıp doldurun
cp .env.example .env
# .env dosyasını açın ve ALTINAPI_API_KEY=doldurun
# (Dashboard'dan hapi_... formatında API Key alın)

# 3. Çalıştırın
python altinapi_poc.py
```

## API Credentials Alma
1. https://altinapi.com/register → Hesap oluştur
2. Dashboard → **API Anahtarı** sayfası → **API Key** (hapi_... formatında)
3. **Plan yükseltin**: Pro (60/dk, 3 WS) veya Enterprise (10 WS) - WebSocket için zorunlu

## Çalıştırma
```bash
python altinapi_poc.py
```

## Test Edilenler (Resmi Dokümantasyona Uygun)
1. REST Snapshot (`GET /api/v1/prices` + `X-API-Key` header)
2. Socket.io bağlantısı (`https://altinapi.com`, Socket.io)
3. Auth: `auth: {api_key: "hapi_..."}` (resmi format)
4. `prices:snapshot` (bağlantı anında tüm fiyatlar)
5. `prices:update` (gerçek zamanlı güncellemeler)
6. `subscribe` / `unsubscribe` (DOVIZ, MADEN, SARRAFIYE kategorileri)
7. `data:stale` / `data:live` eventleri
8. 5 dakika event loglama
9. Reconnect testi (bağlantı kesilip tekrar)

## Semboller (Resmi Liste)
| Kategori | Semboller |
|----------|-----------|
| DOVIZ (16) | USDTRY, EURTRY, GBPTRY, CHFTRY, AUDTRY, CADTRY, JPYTRY, SARTRY, DKKTRY, NOKTRY, SEKTRY, EURGBP, EURCHF, EURUSDS, XUSDTRY, FARKEUR |
| MADEN (19) | ALTIN, XAUUSD, XAUUSDS, XAUEUR, XAUXAG, GUMTRY, GUMUSD, XAGUSD, KXAGUSD, PLATIN, XPTUSD, PALADYUM, XPDUSD, PARUSD, PAREUR, PARGBP, PARCHF, FARK, VADE FARK |
| SARRAFIYE (15) | CEYREK_YENI, CEYREK_ESKI, YARIM_YENI, YARIM_ESKI, TEK_YENI, TEK_ESKI, ATA_YENI, ATA_ESKI, ATA5_YENI, ATA5_ESKI, GREMESE_YENI, GREMESE_ESKI, AYAR22, AYAR14, KULCEALTIN |

## Ölçülen Metrikler
- Sembol başına update interval: min/median/p95/avg/max (ms)
- Latency (provider timestamp → local receive)
- Duplicate event oranı
- Snapshot alma süresi
- Reconnect başarı/süre

## Hata Kodları (Resmi)
| Kod | Anlam | Çözüm |
|-----|-------|-------|
| 401 | Invalid API key | Key format: hapi_... |
| 403 | Forbidden | Plan/WS erişimi yok, IP whitelist |
| 429 | Rate limit | Plan limiti aşıldı |
| 503 | Stale data | Provider bağlantısı kesildi |

## Çıktı: Yahoo 3s Polling ile Karşılaştırma

| Metrik | Yahoo 3s | altinapi.com |
|--------|----------|--------------|
| Update Interval | 3000ms (fixed) | median/p95/avg (ms) |
| Latency | ~500ms | avg (ms) |
| Speedup | 1x | Nx |

## Sonuç: "Evet/Hayır"
> "altinapi.com WebSocket gerçekten gerçek zamanlı davranışı sağlıyor mu?"

- **EVET** (sub-second median interval, <200ms latency, düşük duplicate) → Production plan
- **HAYIR** → Nedeni raporla

## Sık Hatalar ve Çözümler
| Hata | Neden | Çözüm |
|------|-------|-------|
| 401 Unauthorized | Key format/expired | Key format: `hapi_...` |
| 403 Forbidden | Plan/WS erişimi yok | Pro+ plan gerekli (Free/Starter WS yok) |
| 403 Forbidden | IP whitelist | Dashboard'dan IP ekle |
| Bağlantı yok | Plan WS yok | Pro+ plan gerekli (Free/Starter WS yok) |
| 429 Rate limit | Limit aşıldı | Plan limiti aşıldı |