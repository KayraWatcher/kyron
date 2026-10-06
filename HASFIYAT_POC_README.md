# Hasfiyat WebSocket PoC - Kullanım Kılavuzu

## Amaç
Hasfiyat WebSocket API'sinin **gerçek zamanlı** (sub-second) FX + Altın + Gümüş veri akışını doğrulamak. Mevcut Yahoo 3 saniyelik HTTP polling ile karşılaştırmak.

## Gereksinimler
- Python 3.8+
- Hasfiyat API hesap (panelden API Key + JWT Token alınması gerekir)

## Kurulum

```bash
# 1. Bağımlılıkları yükle
pip install websockets aiohttp python-dotenv

# 2. .env.example kopyalayıp doldurun
cp .env.example .env
# .env dosyasını açın ve şunları doldurun:
# - HASFIYAT_API_KEY (REST API için Bearer token)
# - HASFIYAT_JWT_TOKEN (WebSocket için token - panelden alınan)
# - HASFIYAT_SOURCE (varsayılan: harem)
# - HASFIYAT_SYMBOLS (izlenecek semboller, virgülle ayrılmış)

# 3. Çalıştırın
python hasfiyat_poc.py
```

## API Credentials Alma
1. https://altinapi.hasfiyat.com → Giriş yap / Kayıt ol
2. Panel → **API Anahtarı** sayfası → **API Key** (REST için) + **JWT Token** (WebSocket için) oluşturun
3. IP/Domain whitelist ekleyin (gerekirse)

## Çalıştırma

```bash
python hasfiyat_poc.py
```

## Çıktı Analizi

Script şunları test eder ve raporlar:

1. **REST Snapshot** - Bağlantı öncesi anlık fiyat alma
2. **WebSocket Bağlantısı** - Bağlantı kurulum süresi, handshake
3. **Event Dinleme (5 dakika)** - Tick event'lerini toplar
4. **Reconnect Testi** - Bağlantı kesilip tekrar denenir
5. **İstatistikler**:
   - Event sayısı, duplicate sayısı, hata sayısı, reconnect sayısı
   - Sembol başına update interval dağılımı (min/median/p95/max/avg)
   - Latency (event→receive) dağılımı
   - Duplicate event oranı
5. **Market Closed Check** - Piyasa kapalıysa uyarı

## Karşılaştırma Çıktısı

Script sonunda şu tabloyu üretir:

| Metrik | Yahoo 3s Polling | Hasfiyat WebSocket |
|--------|------------------|-------------------|
| Update Interval | 3000ms (fixed) | median/avg/p95 (ms) |
| Latency | ~500ms | avg (ms) |
| Protocol | HTTP polling | WebSocket (persistent) |
| Speedup | 1x | Nx faster |
| Duplicate Rate | 0% | % |
| Errors | - | count |

## Sonuç Yorumlaması

**✅ BAŞARILI Kriterler:**
- Event sayısı > 10 (5 dakikada)
- Median update interval < 1000ms (sub-second)
- Avg latency < 200ms
- Duplicate oranı < 10%
- USDTRY sembolü event alıyor
- Reconnect başarılı

**❌ BAŞARISIZ Kriterler:**
- Event sayısı = 0 veya çok az
- Median interval > 3000ms (Yahoo'dan yavaş)
- Bağlantı kurulamıyor / sürekli disconnect
- API key/token geçersiz (401/403)
- Sembol mapping hatası (USDTRY event gelmiyor)

## Sonuç Raporu

Script sonunda şu soruya **kesin cevap** verir:

> **"USD/TRY için Hasfiyat WebSocket gerçekten GOLD'un istediği gerçek zamanlı davranışı sağlıyor mu?"**

- **EVET** → Production entegrasyon planı çıkarılır
- **HAYIR** → Nedeni raporlanır, GOLD koduna dokunulmaz

## Log Dosyası

Detaylı event logları terminal çıktısında görünür. İsterseniz dosyaya yönlendirin:
```bash
python hasfiyat_poc.py 2>&1 | tee poc_log_$(date +%Y%m%d_%H%M%S).txt
```

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| `HASFIYAT_API_KEY not set` | `.env` dosyasını kontrol edin |
| `401 Unauthorized` | API Key/JWT Token geçersiz, panelden yeniden oluşturun |
| `403 Forbidden` | IP whitelist eksik, panelden IP ekleyin |
| `Connection refused` | `wss://api.hasfiyat.com/stream` erişilebilir mi kontrol edin (firewall/proxy) |
| `USDTRY event gelmiyor` | Sembol mapping kontrolü: `USD/TL` → `USDTRY` normalizasyonu script'te var |
| `Event gelmiyor ama bağlantı var` | Piyasa kapalı olabilir (hafta sonu, gece) - market hours kontrolü |
| `Duplicate %100` | Aynı veri tekrar geliyor - provider taraflı, deduplication gerekir |

## Lisans Doğrulama (Manuel)

PoC çalıştırılmadan önce Hasfiyat dokümantasyonundan şunları doğrulayın:
1. **Mobil uygulama lisansı** - Gold paketinde "mobil uygulama fiyat ekranı" lisansı var mı?
2. **Yeniden dağıtım** - Veri mobil uygulamada gösterilebilir mi?
3. **API şartları** - Rate limit, connection limit, uptime SLA
4. **Veri kaynağı** - 11 kaynak (Harem, Hakan, Mayda, vb.) gerçek mi?

Dokümantasyon: https://altinapi.hasfiyat.com/docs
Pazaryeri entegrasyonu (mobil uygulama lisansı kanıtı): https://altinapi.hasfiyat.com/pazaryerleri

## Sonraki Adımlar

1. PoC başarılıysa → `HASFIYAT_POC_RESULTS.md` yaz → Production entegrasyon planı
2. PoC başarısızsa → Nedenini raporla → GOLD koduna dokunma
3. Matriks Data için ayrı PoC planla (BIST + OHLC için)