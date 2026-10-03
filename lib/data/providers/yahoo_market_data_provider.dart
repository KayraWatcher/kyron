import '../../core/error/failures.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import 'yahoo_finance_provider.dart';

/// Yahoo Finance kaynakli [MarketDataProvider] uyarlamasi.
///
/// Kapsam: BIST endeks/hisse + uluslararasi ons altin/gumus + doviz
/// **degisim orani** (yalnizca [id] `tcmb` saglayicisi tarafindan kullanilir).
///
/// Yahoo'nun bid/ask verisi yoktur; bu nedenle alis/satis alanlari **null**
/// birakilir ve UI "—" gosterir. Uydurma deger uretilmez.
class YahooMarketDataProvider implements MarketDataProvider {
  YahooMarketDataProvider(this._yahoo);

  final YahooFinanceProvider _yahoo;

  @override
  String get id => 'yahoo';

  @override
  String get displayName => 'Yahoo Finance';

  @override
  bool supports(String assetId) {
    final asset = AssetCatalog.byId(assetId);
    if (asset == null || asset.isCalculated) return false;
    // Dovizin fiyati TCMB'dedir; Yahoo yalnizca degisim oraninda kullanilir.
    return asset.category != AssetCategory.doviz;
  }

  @override
  Duration get refreshInterval => _refreshInterval;

  /// Listelerin (Ana Sayfa / Piyasalar / Takip) tazeleme ritmi.
  ///
  /// Yahoo `chart` ucu **sembol basina** istek atar (partlu degil).
  /// Ana Sayfa ~6 benzersiz sembol istedigi icin 3 sn'de bir toplam ~2
  /// istek/sn gider; uygulama acikken sembol basina saatte ~1200 istek.
  ///
  /// Bu ritim bilincli olarak hizlandirildi (v2 - kullanici talebi:
  /// "ana sayfada her 2-3 saniyede yenilensin") ve iki korumayla desteklendi:
  ///
  ///  1. **Ustel geri cekilme**: `MarketDataRepository.watchQuotes` ag
  ///     hatasi / 429 alirsa ritmi 2, 4, 8 ... katina cikarir (en fazla
  ///     60 sn), basari gorunce normale doner. Saglayici asla zorlanmaz.
  ///  2. **Yalanci canlilik yok**: daha kisa aralik veriyi *daha hizli
  ///     yapmaz* - Yahoo'nun ucretsiz beslemesinde gercek zamanli akis
  ///     (WebSocket) yoktur, bu nedenle tazelik [DataFreshness.delayed]
  ///     olarak kalir; "Canlı" etiketi asla kullanilmaz.
  static const Duration _refreshInterval = Duration(seconds: 3);

  @override
  bool supportsCandles(String assetId) {
    final asset = AssetCatalog.byId(assetId);
    if (asset == null || asset.isCalculated) return false;
    // Fiyat istegi dövizde TCMB'den gelir; **mum** (OHLC) serisi icin ise
    // TCMB'de veri yoktur - parite mumu Yahoo'dan alinir. Boylece hesaplanan
    // gram altin grafiği de (ons x USD/TRY) calisir.
    return true;
  }

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final ids = assetIds.where(supports).toList();
    if (ids.isEmpty) {
      return const Err(EmptyFailure('Yahoo Finance için uygun sembol yok.'));
    }

    // Varlik -> sembol eslemesi; ayni sembole dusenler tek istekte toplanir.
    final bySymbol = <String, List<String>>{};
    for (final id in ids) {
      final asset = AssetCatalog.byId(id);
      if (asset == null) continue;
      bySymbol.putIfAbsent(asset.fetchSymbol, () => []).add(id);
    }
    if (bySymbol.isEmpty) {
      return const Err(EmptyFailure('Sembol eşlenemedi.'));
    }

    final res = await _yahoo.fetchQuotes(bySymbol.keys);
    final metas = res.dataOrNull;
    if (metas == null) return Err(res.failureOrNull ?? const NetworkFailure());

    final now = DateTime.now();
    final nowUtc = now.toUtc();
    final out = <String, Quote>{};
    for (final entry in bySymbol.entries) {
      final meta = metas[entry.key];
      if (meta == null || !meta.hasData) continue;
      for (final assetId in entry.value) {
        out[assetId] = Quote(
          assetId: assetId,
          source: QuoteSourceLabel.market,
          updatedAt: now,
          price: meta.price,
          previousClose: meta.effectivePreviousClose,
          dayHigh: meta.dayHigh,
          dayLow: meta.dayLow,
          change: meta.effectiveChange,
          changePercent: meta.effectiveChangePercent,
          currency: meta.currency,
          volume: meta.volume,
          marketTime: meta.marketTime,
          freshness: _freshnessOf(meta, nowUtc),
        );
      }
    }

    if (out.isEmpty) {
      return const Err(EmptyFailure('Yahoo Finance fiyat verisi boş döndü.'));
    }
    return Success(out);
  }

  /// Veri tazeligi.
  ///
  /// Yahoo'nun ucretsiz `chart` beslemesi **gercek zamanli akis (stream)
  /// garantisi vermez**; bu nedenle `DataFreshness.live` **uretilmez**.
  ///
  ///  * Oturum bilgisi yoksa  -> [DataFreshness.unknown]
  ///  * Oturum acik           -> [DataFreshness.delayed]
  ///  * Oturum kapali         -> [DataFreshness.closed]
  static DataFreshness _freshnessOf(YahooQuoteMeta meta, DateTime nowUtc) {
    if (!meta.hasTradingSession) return DataFreshness.unknown;
    return meta.isMarketOpenAt(nowUtc)
        ? DataFreshness.delayed
        : DataFreshness.closed;
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    if (!supportsCandles(assetId)) {
      return const Err(EmptyFailure('Bu kaynak mum verisi desteklemiyor.'));
    }
    final asset = AssetCatalog.byId(assetId);
    if (asset == null) {
      return Err(BadRequestFailure('$assetId tanımlı değil.'));
    }

    final res = await _yahoo.fetchCandles(
      symbol: asset.fetchSymbol,
      interval: interval,
      limit: limit,
    );

    return res.when(
      onSuccess: (series) => Success(CandleSeries(
        assetId: assetId,
        interval: interval,
        candles: series.candles,
        updatedAt: DateTime.now(),
      )),
      onFailure: (f) => Err(f),
    );
  }
}
