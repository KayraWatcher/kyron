# GOLD v2 & Encoding Task - Complete Report

## Final Gates (run from C:\goldproj)
- `dart analyze --format machine` → **exit 0 (clean)**
- `flutter test` → **268/268 passed**
- `flutter test test/live_market_check.dart` → **5/5 passed**
- `flutter build apk --release` → **exit 0 → 56.5 MB**
- `adb install -r` → **Success**

## Completed v2 Areas (chronological + new)
| Faz / Area | Durum |
|---|---|
| Faz A — DataFreshness (live/delayed/daily/closed/unknown, ranks 4/3/2/1/0) | ✅ DONE |
| Faz B — MarketDataProvider.refreshInterval (Yahoo 30s → 3s, TCMB 5dk) | ✅ DONE |
| Faz C — watchQuotes(ids, {interval, isActive}); success→fresh, later→lastGood isStale + auto-retry; first→addError; inFlight guard | ✅ DONE |
| Faz D — home_display.dart: prefsKey='home_display.v1' persistence + _restore/_persist (same pattern as theme) | ✅ DONE |
| Faz D — Header label 'Tümü' when filter==onecikanlar; else display.filter.label; onAction opens showHomeDisplaySheet | ✅ DONE |
| Faz D — filter/sort device verification: Altın→only gold cards; Fiyat+Azalan→Çeyrek>Gram>Ons; assets without quotes excluded; header action='Altın'; persistence survived force-stop+relaunch; tapping 'Altın' label opens sheet | ✅ DONE |
| Faz E — CandleOhlcBar Wrap (horizontal SingleChildScrollView→Wrap, spacing:0, runSpacing:2, center) | ✅ DONE |
| Faz E — ChartWindow invariants: minVisible=8, maxVisible=500, clampVisible/clampFirst/zoomVisible/scaledVisible/panFirst → first+visible<=n (no right blank) | ✅ DONE |
| Faz E — CandleOhlcBar header: A/Y/D/K + hacim + tarih of crosshair candle (else last) | ✅ DONE |
| Faz E — interval honesty: 1wk/1mo both end with identical partial-period candle at 2026-10-02 20:59 UTC (=2 Ekim 23:59 TRT) | ✅ DONE |
| Faz E — header: OHLC/volume/date reflects crosshair-selected candle | ✅ DONE |
| Faz F — rebuild narrowing: _Header watches assetQuoteProvider(assetId); detail watches quote only when _tab==1; computedIndicatorsProvider watch moved into _ChartSection; alert badge uses ref.watch(alertsProvider.select(...)) | ✅ DONE |
| Crosshair on device → long press triggers crosshair; pan (_onScaleStart) hides crosshair | ✅ DONE |
| Interval probe (9 chips = 9 intervals) + live market check + crosshair device verification | ✅ DONE |
| Faz D filter/sort device verification | ✅ DONE |
| Streaming research (doc block in interface file) + contract tests assert no current provider is Streamable | ✅ DONE |
| Footer imza ("Kayra ÇIKLA") | ✅ DONE |
| TrFormat.dateTimeSeconds | ✅ DONE |

## New Additions (post-v2-base)
1. **crosshairCandleProvider** — `NotifierProvider.autoDispose.family<CrosshairPickNotifier, Candle?, String>`; assetId'li, sayfa kapatınca sıfırlanır; `_syncCrosshairCandle` + `resolveCrosshairCandle` + `crosshairChanged` yardımcıları.
2. **resolveCrosshairCandle()** — endeks clamping (dışa cikana uydurmaz; ilk/son mum), bozer seri → null.
3. **crosshairChanged()** — null-equal, geçiş, aynı-mum içinde (Faz F: yeniden kurulmaz), farklı-mum (Faz F: yeniden kurar).
4. **data_layer_test.dart** — backoff testi (ag hatası surekliysa ritmik uzama + basari sonrası normale donme); focusedQuoteRefreshInterval doğrulama.
5. **TrFormat.dateTimeSeconds** — "`2 Ekim 2026, 14:32:07`" formatı; state_view.dart updated.
6. **Footer imza** — En alttaya `GOLD · Türkiye piyasa takibi / Geliştirici: Kayra ÇIKLA`.
7. **Faz B yorum güncellemesi** — Yahoo 3sn, TCMB 5dk; detailed doc comments.

## Testler
- `test/crosshair_pick_test.dart` — yeni saf (pure) cozumleme katmanı.
- `test/data_layer_test.dart` — backoff + freshness + refreshInterval testleri (268 geneli).
- Tüm 268 test geçti; analyze 0 hata.

## Kalan / Bekleyen (14 nolu device check)
1. Chart-pan pixel analysis — `System.Drawing.Bitmap` null hatası (`pan0.png` load failed). Invariants + UI gözlemmesi yeterli; APK sağlıyor.
2. Background/Foreground cycle → `cmd connectivity airplane-mode enable → disable`; ~10 min stabilite; stale→fresh recovery.
3. Haberler encoding taskı — **koleksiyon aşamasında** (RSS/HTTP charset decode, "YatAtrA+m" gibi bozuklar → düzgün Türkçe). **Tek tek replace hack yapmayın; charset/encoding katmanını düzeltin.**
4. Economic calendar source (licensing → STOP).

## APK
`C:\goldproj\build\app\outputs\flutter-apk\app-release.apk` — **56.5 MB**, `adb install -r` → Success.

## ÖNEMLİ Uyarılar
- **Yeni özellik geliştirmeye geçmeden önce** TÜM yarım bırakılan işleri (yukarıdaki "Kalan") tamamen temizle.
- **Sahte/random piyasa verisi kullanma.** (STRICT data rules)
- **Mevcut Yahoo 3sn polling sistemini, yeni sağlayıcı doğrulanmadan değiştirme.** (Ayrı görev)
- **Mevcut çalışan özellikleri (grafik, crosshair, filtre, sıralama, portfolio) bozma.**
- **Tamamlanmış işleri gereksiz yere yeniden yazma.** (Bir önceki görevden SONRA yapılacak.)
- **Encoding task: Tek tek karakter replace ederek hack yapma.** HTTP response charset/encoding işlemini kontrol et; RSS/XML encoding declaration'ı kontrol et; UTF-8/ISO-8859-9/Windows-1254 gibi olası charset problemlerini doğru şekilde ele al; HTML entity decoding'i doğru yap; "£ orijinal habere git" gibi bozuk metinleri de kontrol et; Haber başlığı, özet, kaynak adı ve diğer metinlerde aynı encoding problemi olmadığını kontrol et; Gerçek Anadolu Ajansı RSS verisiyle Android cihaz üzerinde test et.

## Son
Tüm başarılar, analizler ve APK konumları yukarıda belgelenmiştir. Yeni özellik geliştirmeden önce yarım bırakılan (lifecycle, encoding, chart-pan invariants) işleri tamamlanmalıdır.