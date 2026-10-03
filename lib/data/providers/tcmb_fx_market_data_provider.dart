import '../../core/error/failures.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import 'tcmb_currency_provider.dart';
import 'yahoo_finance_provider.dart';

/// TCMB serbest piyasa kaynakli [MarketDataProvider] uyarlamasi.
///
/// Kapsam: USD/EUR/GBP/CHF/JPY -> TRY kurlari.
///
/// ## Alan kaynaklari (bilesik - hepsi gercek kaynak)
///  * `price` / `bid` / `ask` -> **TCMB** gunluk XML (resmi, anahtarsiz).
///  * `previousClose`         -> **Yahoo Finance** ayni sembolun gunluk
///    degisim oranindan TCMB tabanina yeniden olceklenerek uretilir.
///
/// ### Neden boyle?
/// TCMB `today.xml` beslemesi yalnizca **bugunku** kurlari icerir ve tarihsel
/// dosyalar (`/kurlar/YYYYMM/YYYYMMDD.xml`) artik **404** dondurur. Boylece
/// onceki kapanis TCMB'den dogrudan alinamaz. Deger **uydurulmaz**: Yahoo'nun
/// yayinladigi `%degisim` alinir ve TCMB'nin anlik mid degeri uzerinden
/// `oncekiKapanis = guncel / (1 + oran/100)` formuluyle geri hesaplanir.
/// Boylece `Quote.effectiveChangePercent` birebir kaynaktaki oranla eslesir.
///
/// Yahoo erisilemezse `previousClose` **null** kalir ve UI "%" yerine
/// "—" gosterir - isteger ayrica istemez.
///
/// ## Mum verisi
/// TCMB gunluk kurlarinda OHLC yoktur; `supportsCandles` **false** doner.
class TcmbFxMarketDataProvider implements MarketDataProvider {
  TcmbFxMarketDataProvider(this._tcmb, {this.yahoo});

  final TcmbCurrencyProvider _tcmb;

  /// %degisim icin kullanilan ikincil kaynak (opsiyonel).
  final YahooFinanceProvider? yahoo;

  @override
  String get id => 'tcmb';

  @override
  String get displayName => 'TCMB';

  @override
  bool supports(String assetId) {
    final asset = AssetCatalog.byId(assetId);
    if (asset == null || asset.isCalculated) return false;
    return asset.category == AssetCategory.doviz;
  }

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Duration get refreshInterval => _refreshInterval;

  /// TCMB `today.xml` **gunde bir aciklanan resmi** kurdur.
  ///
  /// Kur gunde birkac kez (sabah acilisi + olasi duzeltmeler) yeniden
  /// yayinlanir; 5 dakikadan hizli sorgulamak yeni veri getirmez, yalnizca
  /// gereksiz trafik uretir. Boylece aralik saglayicinin **destekledigi en
  /// hizli anlamlı seviyede** kalir ve tazelik [DataFreshness.daily] olarak
  /// etiketlenir - "Canlı" yazisi uretilmez.
  static const Duration _refreshInterval = Duration(minutes: 5);

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final ids = assetIds.where(supports).toSet().toList();
    if (ids.isEmpty) {
      return const Err(EmptyFailure('Desteklenen döviz sembolü bulunamadı.'));
    }

    final codes = <String>{};
    for (final id in ids) {
      final asset = AssetCatalog.byId(id);
      if (asset != null) codes.add(asset.symbol);
    }

    final rateRes = await _tcmb.fetchCurrencies(codes);
    final rates = rateRes.dataOrNull;
    if (rates == null) {
      return Err(rateRes.failureOrNull ?? const NetworkFailure());
    }

    final pcts = await _fetchChangePercents(ids);

    final now = DateTime.now();
    final out = <String, Quote>{};

    for (final id in ids) {
      final asset = AssetCatalog.byId(id);
      if (asset == null) continue;
      final rate = rates[asset.symbol];
      if (rate == null || !rate.hasData) continue;

      final mid = rate.mid;
      if (mid == null || !mid.isFinite || mid <= 0) continue;

      out[id] = Quote(
        assetId: id,
        source: QuoteSourceLabel.market,
        updatedAt: now,
        price: mid,
        bid: rate.buying,
        ask: rate.selling,
        previousClose: _rebasedPreviousClose(mid, pcts[asset.fetchSymbol]),
        currency: 'TRY',
        // TCMB `today.xml` gunde bir aciklanan **resmi** kurdur; bu besleme
        // asla canli akis degildir, boylece "Canlı" etiketi uretilmez.
        freshness: DataFreshness.daily,
      );
    }

    if (out.isEmpty) {
      return const Err(EmptyFailure('TCMB kur verisi boş döndü.'));
    }
    return Success(out);
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure(
        'TCMB günlük kurlarında OHLC mum verisi bulunmuyor.',
      ));

  // ---------------------------------------------------------------------------
  // Yardimcilar
  // ---------------------------------------------------------------------------

  /// Yahoo yayinindaki yuzde orani TCMB tabanindaki onceki kapanisa cevirir.
  ///
  /// Oran yoksa / gecersizse `null` donulur - deger **uydurulmaz**.
  double? _rebasedPreviousClose(double current, double? percent) {
    if (percent == null || !percent.isFinite || percent <= -100) return null;
    final base = 1 + percent / 100;
    if (base == 0) return null;
    final prev = current / base;
    if (!prev.isFinite || prev <= 0) return null;
    return prev;
  }

  /// Simdiye kadar cekilen onceki kapanis degerleri (gunluk).
  final Map<String, (DateTime, double?)> _pctCache = {};

  /// Yahoo'dan döviz paritesinin gunluk degisim oranlarini ceker.
  ///
  /// Basarisiz olursa hicbir deger uydurulmaz; oranlar `null` kalir.
  Future<Map<String, double?>> _fetchChangePercents(List<String> ids) async {
    final source = yahoo;
    if (source == null) return const {};

    final symbols = <String>{};
    for (final id in ids) {
      final asset = AssetCatalog.byId(id);
      if (asset != null) symbols.add(asset.fetchSymbol);
    }
    if (symbols.isEmpty) return const {};

    // Sembol -> bugun zaten cekildiyse tekrar isteme.
    final today = DateTime.now();
    final cached = <String, double?>{};
    final missing = <String>{};
    for (final s in symbols) {
      final hit = _pctCache[s];
      if (hit != null && hit.$1.year == today.year &&
          hit.$1.month == today.month &&
          hit.$1.day == today.day) {
        cached[s] = hit.$2;
      } else {
        missing.add(s);
      }
    }
    if (missing.isEmpty) return cached;

    final res = await source.fetchQuotes(missing);
    final metas = res.dataOrNull;

    // **Basarisiz cekim gunluk damgalanmaz.** Eski hata: hata durumunda da
    // `_pctCache[s] = (bugun, null)` yazildigi icin sabahtaki gecici bir
    // Yahoo hatasi butun gun "%" alanini "—" yapiyordu; sonraki denemeler
    // de "bugun zaten cekildi" diye cache'e uydugundan hic tekrar denenmiyordu.
    // Artik hata yalnizca bu cagri icinde null dondurur; TCMB 5 dakikalik
    // yenilemesinde Yahoo tekrar denenir.
    if (metas == null) {
      for (final s in missing) {
        cached[s] = null;
      }
      return cached;
    }

    // Basarili cekimde sembol icin sonuc (deger yoksa null) gunluk saklanir:
    // kaynakta o parite gercekten yoksa gereksiz istek tekrarlanmaz.
    for (final s in missing) {
      final pct = metas[s]?.effectiveChangePercent;
      final valid = (pct != null && pct.isFinite) ? pct : null;
      _pctCache[s] = (today, valid);
      cached[s] = valid;
    }
    return cached;
  }
}
