import 'dart:async';

import '../../core/error/failures.dart';
import '../../core/error/state_failure.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import '../../domain/repositories/market_data_repository.dart';

/// Altin/Gumus hesaplamalarinda kullanilan sabitler.
abstract final class MetalMath {
  /// 1 troy ons = 31.1034768 gram.
  static const double gramsPerOunce = 31.1034768;

  /// Gram altin = (ons x USD/TRY) / 31.1035
  static double? gramFromOunce(double ounceUsd, double usdTry) {
    if (!ounceUsd.isFinite || !usdTry.isFinite) return null;
    final v = ounceUsd * usdTry / gramsPerOunce;
    return v.isFinite && v > 0 ? v : null;
  }

  /// Iki bagimsiz getiri oraninin birlesimi.
  ///
  /// Orn. `gram altin = ons altin x USD/TRY` oldugundan, gram altinin
  /// yuzde degisimi tek basina onsin degisimi **degildir**; iki bileşenin
  /// getirileri carpilarak birlestirilir:
  ///
  /// `((1 + a/100) * (1 + b/100) - 1) * 100`
  ///
  /// Girdilerden biri yoksa digeri oldugu gibi gecer; ikisi de yoksa `null`
  /// donulur (uydurma yok).
  static double? combinePercents(double? a, double? b) {
    final va = (a != null && a.isFinite) ? a : null;
    final vb = (b != null && b.isFinite) ? b : null;
    if (va == null && vb == null) return null;
    if (va == null) return vb;
    if (vb == null) return va;
    final v = ((1 + va / 100) * (1 + vb / 100) - 1) * 100;
    return v.isFinite ? v : null;
  }
}

/// Turk piyasasindaki darphane/ayar carpanlari (gram karsiligi).
abstract final class GoldWeights {
  static const double ceyrek = 1.75;
  static const double yarim = 3.50;
  static const double tam = 7.00;
  static const double cumhuriyet = 7.216;
  static const double ata = 7.216;
  static const double bilezik22 = 0.916; // saflik carpani
}

/// Sonuc + olasi basarisizlik. Tek seferde hem veri hem hata tasir.
typedef _Fetched = ({Map<String, Quote> quotes, Failure? failure});

/// Ana market repository implementasyonu.
///
/// **Kaynaklar [MarketDataProvider] arayuzu uzerinden gelir**; bu sinif
/// yalnizca *orkestratordur*: hangi varligin hangi kaynaktan alinacagini
/// secer, onbellek tutar ve **hesaplanan** (turev) degerleri uretir.
///
/// Varsayilan kaynaklar:
///   * TCMB  -> USD/EUR/GBP/CHF/JPY kurlari (dogrudan, resmi kaynak)
///   * Yahoo -> BIST endeks/hisse + ons altin/gumus (dogrudan)
///   * Hesap -> gram altin/gumus, muhtelif altin cesitleri (HESAPLANAN)
///
/// Hesaplanan degerler [QuoteSourceLabel.calculated] ile isaretlenir ve
/// UI'da "hesaplanan" etiketiyle gosterilir. Yeni bir kaynak eklemek icin
/// [MarketDataProvider] uygulayip [sources] listesine eklemek yeterlidir.
class MarketDataRepositoryImpl implements MarketDataRepository {
  MarketDataRepositoryImpl({
    required List<MarketDataProvider> sources,
    this.staleAfter = const Duration(seconds: 60),
  }) : sources = List.unmodifiable(sources);

  /// Sira onemlidir: onceki kaynak desteklerse o kazanir.
  final List<MarketDataProvider> sources;
  final Duration staleAfter;

  /// Kisayonbellek: ayni varlik icin tekrar tekrar cagriyi onler.
  final Map<String, _CacheEntry<Quote>> _quoteCache = {};
  final Map<String, _CacheEntry<CandleSeries>> _candleCache = {};

  /// **Ayni anda yuruyen istek birlestirilir (in-flight coalescing).**
  ///
  /// Neden: `IndexedStack` sayesinde Ana Sayfa ve Piyasalar **ayni anda**
  /// yasar; ikisi de ~3 sn'de bir ayni sembolleri ister. Onbellek TTL'i
  /// her iki taraf da ayni anda dondugu icin ayni anda dolar, yani istek
  /// **iki kez** ayni anda aga giderdi. Burada ayni anahtara sahip ikinci
  /// cagri, ilkinin gelecegini **paylasir**; saglayiciya tek istek gider.
  final Map<String, Future<_Fetched>> _quoteInFlight = {};
  final Map<String, Future<Result<CandleSeries>>> _candleInFlight = {};

  // ---------------------------------------------------------------------------
  // KAYNAK SECIMI
  // ---------------------------------------------------------------------------

  MarketDataProvider? _quoteSourceFor(String assetId) {
    for (final s in sources) {
      if (s.supports(assetId)) return s;
    }
    return null;
  }

  /// Varligin **fiyat onbellek suresi** = besleyen saglayicinin araligi.
  ///
  /// Boylece zamanlayici ile onbellek **her zaman ayni ritimde** calisir:
  /// zamanlayici her tetiklendiginde onbellek suresi dolmustur ve gercek bir
  /// istek gider. Ayni zamanda saglayicinin araliginin altina inilmez -
  /// gereksiz/yinelenen API cagrisi uretilmez.
  ///
  /// Hesaplanan varliklarda sure **bilesenlerin en hizlisidir**: gram altinin
  /// onbellek suresi, onsin veya USD/TRY'nin suresinden uzun olursa yeni
  /// onsin gelmesine ragmen gram altin bayat kalir.
  Duration _quoteTtlFor(String assetId) {
    final asset = AssetCatalog.byId(assetId);
    if (asset != null && asset.isCalculated && asset.parentIds.isNotEmpty) {
      Duration? best;
      for (final p in asset.parentIds) {
        final d = _quoteTtlFor(p);
        if (best == null || d < best) best = d;
      }
      if (best != null) return best;
    }
    return _quoteSourceFor(assetId)?.refreshInterval ?? staleAfter;
  }

  MarketDataProvider? _candleSourceFor(String assetId) {
    for (final s in sources) {
      if (s.supportsCandles(assetId)) return s;
    }
    return null;
  }

  /// Asset'i dogrudan destekleyen EN ONCELI provider'i dondurur.
  /// Provider listesi zaten priority sirasinda (TCMB -> Anlik -> Yahoo).
  MarketDataProvider? _quoteSourceForDirect(String assetId) {
    for (final s in sources) {
      if (s.supports(assetId)) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // QUOTE
  // ---------------------------------------------------------------------------

  @override
  Future<Result<Quote>> getQuote(String assetId) async {
    final res = await getQuotes([assetId]);
    return res.when(
      onSuccess: (map) {
        final q = map[assetId];
        if (q == null) {
          return Err(EmptyFailure('$assetId için fiyat bulunamadı.'));
        }
        return Success(q);
      },
      onFailure: (f) => Err(f),
    );
  }

  @override
  Future<Result<Map<String, Quote>>> getQuotes(List<String> assetIds) async {
    if (assetIds.isEmpty) return const Err(EmptyFailure('Varlık listesi boş.'));

    // 1) Onbellekten taze olanlari al.
    final now = DateTime.now();
    final result = <String, Quote>{};
    final missing = <String>[];

    for (final id in assetIds.toSet()) {
      final cached = _quoteCache[id];
      if (cached != null && now.difference(cached.at) < _quoteTtlFor(id)) {
        result[id] = cached.value;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return Success(result);

    Failure? lastFailure;

    // 2) HER eksik varlik icin once DOGRUDAN provider dene (isCalculated bagimsiz).
    // Provider priority: TCMB -> AnlıkAltınFiyatlari -> Yahoo
    // _fetchDirectTryAll, provider'lari priority sirasiyla dener ve ilk basarili
    // direct quote'u dondurur. isCalculated true olsa bile direct provider
    // varsa kullanilir.
    final directResult = await _fetchDirectTryAll(missing);
    result.addAll(directResult.quotes);
    lastFailure = directResult.failure;

    // 3) Hala eksik olanlar icin: derived/calculated fallback.
    // Sadece isCalculated==true OLAN assetlerin parent bileşenlerini cekmeye calis.
    // Non-calculated assetler zaten step 2'de denenmistir.
    final stillMissing = missing.where((id) => !result.containsKey(id)).toList();
    if (stillMissing.isNotEmpty) {
      final ordered = _expandAncestors(stillMissing);

      // Sadece calculated assetlerin parent'larini (non-calculated) topla.
      // Bu, ayni assetin tekrar denenmesini onler.
      final ancestors = <String>{};
      for (final id in ordered) {
        if (AssetCatalog.byId(id)?.isCalculated ?? false) {
          final parents = AssetCatalog.byId(id)?.parentIds;
          if (parents != null) {
            for (final p in parents) {
              if (!(AssetCatalog.byId(p)?.isCalculated ?? false) && !result.containsKey(p)) {
                ancestors.add(p);
              }
            }
          }
        }
      }
      final ancestorsList = ancestors.toList();

      if (ancestorsList.isNotEmpty) {
        final r = await _fetchDirectTryAll(ancestorsList);
        result.addAll(r.quotes);
        lastFailure = r.failure ?? lastFailure;
      }

      final derivedIds = [
        for (final id in ordered)
          if (AssetCatalog.byId(id)?.isCalculated ?? false) id,
      ];
      final derived = _deriveAll(derivedIds, result);
      derived.forEach((id, q) {
        result[id] = q;
        _quoteCache[id] = _CacheEntry(q, DateTime.now());
      });
    }

    // 4) Saglayici istenen sembolu atlattisa (istek **hatasiz** dondu ama
    //    bazi id'ler yanitta yer almuyor): onbellekteki SON deger bayat
    //    olarak geri eklenir. Boylece GC=F / SI=F gecici olarak gelmediginde
    //    varligin verisi silinmez; UI `isStale` ile "son bilinen veriler"
    //    gosterir ve saglayici dondugunde tazelenir.
    //
    //    **Yalnizca hatasiz yanitta** uygulanir: ag/saglayici hatasinda
    //    oldugu gibi `Err` doner, boylece ustel geri cekilme (429)
    //    korumasi ve "ilk istek basarisiz" davranisi degismez.
    if (lastFailure == null) {
      for (final id in assetIds) {
        if (result.containsKey(id)) continue;
        final cached = _quoteCache[id]?.value;
        if (cached == null) continue;
        result[id] = cached.isStale ? cached : cached.copyWith(isStale: true);
      }
    }

    if (result.isEmpty) {
      return Err(lastFailure ?? const NetworkFailure());
    }
    return Success(result);
  }

  /// Verilen assetler icin oncelikli sirada tum provider'lari dener.
  /// Ilk basarili direct quote'u dondurur.
  /// Bu, isCalculated=true olsa bile provider destekliyorsa kullanilmasini saglar.
  Future<_Fetched> _fetchDirectTryAll(List<String> assetIds) async {
    final now = DateTime.now();
    final out = <String, Quote>{};
    Failure? failure;

    for (final id in assetIds.toSet()) {
      final cached = _quoteCache[id];
      if (cached != null && now.difference(cached.at) < _quoteTtlFor(id)) {
        out[id] = cached.value;
        continue;
      }

      // Bu asset'i destekleyen provider'lari oncelik sirasiyla dene
      final source = _quoteSourceForDirect(id);
      if (source == null) continue; // Kaynagi olmayan varlik: atlanir.

      final res = await source.fetchQuotes([id]);
      final map = res.dataOrNull;
      if (map == null) {
        failure = res.failureOrNull ?? failure;
        continue;
      }
      map.forEach((id, q) {
        out[id] = q;
        _quoteCache[id] = _CacheEntry(q, now);
      });
    }

    return (quotes: out, failure: failure);
  }

  /// Dogrudan kaynaklardan fiyat ceker (onbellek dahil).
  ///
  /// **Aynı anda yürütülen aynı istek tek isteğe düşer**: ikinci cagri
  /// yuruyen istegin gelecegini bekler (bkz. [_quoteInFlight]).
  Future<_Fetched> _fetchDirect(List<String> assetIds) {
    final key = (assetIds.toSet().toList()..sort()).join('|');
    final running = _quoteInFlight[key];
    if (running != null) return running;

    final future = _fetchDirectRun(assetIds);
    _quoteInFlight[key] = future;
    future.whenComplete(() {
      if (identical(_quoteInFlight[key], future)) _quoteInFlight.remove(key);
    });
    return future;
  }

  Future<_Fetched> _fetchDirectRun(List<String> assetIds) async {
    final now = DateTime.now();
    final out = <String, Quote>{};
    Failure? failure;

    final groups = <(MarketDataProvider, List<String>)>[];
    final bucket = <MarketDataProvider, List<String>>{};

    for (final id in assetIds.toSet()) {
      final cached = _quoteCache[id];
      if (cached != null && now.difference(cached.at) < _quoteTtlFor(id)) {
        out[id] = cached.value;
        continue;
      }
      final source = _quoteSourceFor(id);
      if (source == null) continue; // Kaynagi olmayan varlik: atlanir.
      (bucket[source] ??= []).add(id);
    }

    bucket.forEach((source, ids) => groups.add((source, ids)));
    if (groups.isEmpty) return (quotes: out, failure: failure);

    final responses = await Future.wait(
      groups.map((g) => g.$1.fetchQuotes(g.$2)),
    );

    for (var i = 0; i < groups.length; i++) {
      final res = responses[i];
      final map = res.dataOrNull;
      if (map == null) {
        failure = res.failureOrNull ?? failure;
        continue;
      }
      map.forEach((id, q) {
        out[id] = q;
        _quoteCache[id] = _CacheEntry(q, now);
      });
    }

    return (quotes: out, failure: failure);
  }

  /// Turev varliklarin **tum ust bilesenlerini** kendileriyle birlikte
  /// bagimsiz giris sirasina gore (ust bilesen once) siralar.
  List<String> _expandAncestors(List<String> ids) {
    final out = <String>[];

    void visit(String id) {
      if (out.contains(id)) return;
      final asset = AssetCatalog.byId(id);
      if (asset == null) {
        out.add(id);
        return;
      }
      if (asset.isCalculated) {
        for (final p in asset.parentIds) {
          visit(p);
        }
      }
      out.add(id);
    }

    for (final id in ids) {
      visit(id);
    }
    return out;
  }

  /// Turev degerleri **hesaplama sirasinda** uretir.
  ///
  /// Girdi olarak gereken bilesenler `quotes` icinde hazir olmali; eksik
  /// bilesen varsa ilgili turev degeri **uretilmez** (null/rastgele degil).
  ///
  /// **Onemli**: Eger bir asset icin zaten `quotes` icinde dogrudan provider
  /// quote'u varsa (ornegin AnlikAltinFiyatlari gibi bir saglayicidan gelmis),
  /// o zaman hesaplama **yapilmaz** ve mevcut quote korunur.
  /// Bu, AnlikAltinFiyatlari gibi provider'larin canli fiyatlarinin
  /// formulle hesaplanan degerler tarafina dusmemesini saglar.
  Map<String, Quote> _deriveAll(
    List<String> orderedDerivedIds,
    Map<String, Quote> quotes,
  ) {
    final out = <String, Quote>{};
    final now = DateTime.now();
    // Yeni uretilen degerler siradaki turevler tarafindan kullanilabilir
    // (orn. ceyrek altin gram altin uzerinden hesaplanir).
    final working = Map<String, Quote>.of(quotes);

    for (final id in orderedDerivedIds) {
      final asset = AssetCatalog.byId(id);
      if (asset == null || !asset.isCalculated) continue;

      // Eger bu asset icin zaten dogrudan bir provider quote'su varsa,
      // formulle hesaplayip uzerine yazma; mevcut quote'u koru.
      if (quotes.containsKey(id)) {
        // Zaten dogrudan quote var; hesaplama atla.
        // Boylece AnlikAltinFiyatlari gibi saglayicilarin canli fiyatlari korunur.
        continue;
      }

      final price = _derivedPrice(asset, working);
      if (price == null) continue;

      final q = Quote(
        assetId: id,
        source: QuoteSourceLabel.calculated,
        updatedAt: now,
        price: price,
        currency: 'TRY',
        // Turev varliklarda alis/satis makasi kaynakta yok -> null birakilir.
        bid: null,
        ask: null,
        change: null,
        changePercent: _derivedChangePercent(asset, working),
        // Tazelik bilesenlerinden turetilir; uydurulmaz.
        freshness: _derivedFreshness(asset, working),
      );
      out[id] = q;
      working[id] = q;
    }
    return out;
  }

  double? _derivedPrice(AssetDescriptor a, Map<String, Quote> quotes) {
    if (a.id == AssetCatalog.gramAltinId) {
      final ounce = _priceOf(quotes, AssetCatalog.onsAltinId);
      final usdTry = _priceOf(quotes, AssetCatalog.usdTryId);
      if (ounce == null || usdTry == null) return null;
      return MetalMath.gramFromOunce(ounce, usdTry);
    }
    if (a.id == AssetCatalog.gramGumusId) {
      final ounce = _priceOf(quotes, AssetCatalog.onsGumusId);
      final usdTry = _priceOf(quotes, AssetCatalog.usdTryId);
      if (ounce == null || usdTry == null) return null;
      return MetalMath.gramFromOunce(ounce, usdTry);
    }

    // Tek bilesenli turev (orn. gram altin x ayar carpani).
    final parentId = a.parentIds.isNotEmpty ? a.parentIds.first : null;
    if (parentId == null) return null;
    final base = _priceOf(quotes, parentId) ?? _quoteCache[parentId]?.value.price;
    if (base == null) return null;
    final factor = _factorFor(a.id);
    if (factor == null) return null;
    final v = base * factor;
    return (v.isFinite && v > 0) ? v : null;
  }

  /// Turev varligin yuzde degisimi.
  ///
  /// Tek bilesenlilerde bilesenin orani gecerli; iki bilesenlilerde
  /// getiriler [MetalMath.combinePercents] ile birlestirilir.
  double? _derivedChangePercent(AssetDescriptor a, Map<String, Quote> quotes) {
    if (a.parentIds.isEmpty) return null;
    double? acc;
    for (final pid in a.parentIds) {
      acc = MetalMath.combinePercents(acc, quotes[pid]?.effectiveChangePercent);
    }
    return acc;
  }

  /// Turev varligin veri tazeligi.
  ///
  /// Bilesenlerin tazeligi birlestirilir (bkz. [DataFreshness.combine]):
  /// altin piyasasi kapaliysa gram altin da hareket etmez -> `closed`;
  /// aciksa sonuc en taze bilesen kadar tazedir (USD/TRY gun boyu sabit
  /// kaldigi icin gram altinin guncelleme sikligini onsin akisi belirler).
  ///
  /// Bilesenlerden biri tanimsizsa `unknown` doner - tazelik uydurulmaz.
  DataFreshness _derivedFreshness(
    AssetDescriptor a,
    Map<String, Quote> quotes,
  ) {
    if (a.parentIds.isEmpty) return DataFreshness.unknown;
    final parts = <DataFreshness>[];
    for (final pid in a.parentIds) {
      final parent = quotes[pid] ?? _quoteCache[pid]?.value;
      parts.add(parent?.freshness ?? DataFreshness.unknown);
    }
    return DataFreshness.combine(parts);
  }

  double? _priceOf(Map<String, Quote> quotes, String assetId) {
    final q = quotes[assetId];
    if (q == null || !q.hasPrice) return null;
    return q.price;
  }

  double? _factorFor(String assetId) {
    switch (assetId) {
      case AssetCatalog.ceyrekAltinId:
        return GoldWeights.ceyrek;
      case AssetCatalog.yarimAltinId:
        return GoldWeights.yarim;
      case AssetCatalog.tamAltinId:
        return GoldWeights.tam;
      case AssetCatalog.cumhuriyetAltinId:
        return GoldWeights.cumhuriyet;
      case AssetCatalog.ataAltinId:
        return GoldWeights.ata;
      case AssetCatalog.bilezik22Id:
        return GoldWeights.bilezik22;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // KADANS + AKIS (Data Provider -> Stream -> Repository -> UI)
  // ---------------------------------------------------------------------------

  @override
  Duration refreshInterval(List<String> assetIds) {
    // En hizli guncellenen varlik zamanlayici ritmini belirler; daha yavas
    // varliklar her tikte onbellekten okunur ve **gereksiz istek atilmaz**.
    Duration? best;
    for (final id in assetIds.toSet()) {
      final d = _quoteTtlFor(id);
      if (best == null || d < best) best = d;
    }
    return best ?? staleAfter;
  }

  @override
  Stream<Map<String, Quote>> watchQuotes(
    List<String> assetIds, {
    Duration? interval,
    bool Function()? isActive,
  }) {
    if (assetIds.isEmpty) {
      return Stream<Map<String, Quote>>.error(
        const StateFailure(EmptyFailure('Varlık listesi boş.')),
      );
    }

    final period = interval ?? refreshInterval(assetIds);
    var lastGood = <String, Quote>{};
    var inFlight = false;
    /// Ustel geri cekilme sayaci. Ag hatasi / istek limiti (429) surekli
    /// tekrarlanirsa saglayici zorlanmaz; veri **gercektir ama gecikir**
    /// ve UI "guncel degil" gosterir.
    var failures = 0;
    Timer? timer;

    late StreamController<Map<String, Quote>> controller;

    Future<bool> tick(
      StreamController<Map<String, Quote>> c, {
      required bool initial,
    }) async {
      if (c.isClosed) return false;
      if (inFlight) return true; // Yinelenen istek yok; hata sayilmaz.
      // Arka plan: zamanlayici donmeye devam eder ama ag istegi atilmaz.
      if (isActive != null && !isActive()) return true; // hata degil.
      inFlight = true;
      try {
        final res = await getQuotes(assetIds);
        if (c.isClosed) return false;

        final map = res.dataOrNull;
        if (map != null && map.isNotEmpty) {
          lastGood = map;
          c.add(map);
          return true;
        }

        // Ag hatasi / bos yanit: son GERCEK veriyi koru, ama "guncel degil"
        // olarak isaretle. Zamanlayici kendiliginden yeniden dener.
        if (lastGood.isNotEmpty) {
          c.add({
            for (final e in lastGood.entries)
              e.key: e.value.copyWith(isStale: true),
          });
        } else if (initial) {
          c.addError(StateFailure(res.failureOrNull ?? const NetworkFailure()));
        }
        return false;
      } finally {
        inFlight = false;
      }
    }

    /// Sonraki bekleme suresi: hata yoksa normal ritim, hata varsa ustel
    /// olarak uzar (2x, 4x, 8x ... 16x), 60 sn'de tavan yapar.
    Duration nextDelay() {
      if (failures <= 0) return period;
      var d = period;
      for (var i = 0; i < failures && i < 5; i++) {
        d = d * 2;
      }
      const cap = Duration(seconds: 60);
      return d > cap ? cap : d;
    }

    void arm() {
      timer?.cancel();
      if (controller.isClosed) return;
      timer = Timer(nextDelay(), () async {
        final ok = await tick(controller, initial: false);
        if (controller.isClosed) return;
        if (ok) {
          failures = 0;
        } else if (failures < 5) {
          failures++;
        }
        arm();
      });
    }

    controller = StreamController<Map<String, Quote>>(
      onListen: () async {
        final ok = await tick(controller, initial: true);
        if (controller.isClosed) return;
        if (!ok && failures < 5) failures++;
        arm();
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // CANDLES
  // ---------------------------------------------------------------------------

  @override
  Future<Result<CandleSeries>> getCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
    bool forceRefresh = false,
  }) async {
    final key = '$assetId|${interval.name}|$limit';
    final now = DateTime.now();
    if (!forceRefresh) {
      final cached = _candleCache[key];
      if (cached != null && now.difference(cached.at) < staleAfter * 3) {
        return Success(cached.value);
      }
    }

    final asset = AssetCatalog.byId(assetId);
    if (asset == null) {
      return Err(BadRequestFailure('$assetId tanımlı değil.'));
    }

    // Turev varliklar dogrudan mum verisi almaz; bilesenlerinden hesaplanir.
    if (asset.isCalculated) {
      return _deriveCandles(asset, interval, limit, now);
    }

    final res = await _candlesFromSource(assetId, interval, limit);
    final series = res.dataOrNull;
    if (series == null) {
      // Ag hatasi / saglayici hatasi: daha once GERCEK olarak alinmis seri
      // bayat olarak geri doner (quote yolundaki isle mantik). Boylece tek bir
      // gecici hatada grafik bosalmaz / spinner'a donmez; UI `isStale` ile
      // "son bilinen veri" gosterir.
      final old = _candleCache[key]?.value;
      if (old != null) {
        return Success(
          old.isStale
              ? old
              : CandleSeries(
                  assetId: old.assetId,
                  interval: old.interval,
                  candles: old.candles,
                  updatedAt: old.updatedAt,
                  isStale: true,
                ),
        );
      }
      return Err(res.failureOrNull ?? const NetworkFailure());
    }

    final normalized = CandleSeries(
      assetId: assetId,
      interval: interval,
      candles: series.candles,
      updatedAt: now,
    );
    _candleCache[key] = _CacheEntry(normalized, now);
    return Success(normalized);
  }

  /// Varligin mumunu **mum saglayabilen** ilk kaynaktan alir.
  ///
  /// Aynı anda yuruyen ayni istek birlestirilir (ayni sembol+dilim icin
  /// tek ag istegi) - bkz. [_candleInFlight].
  Future<Result<CandleSeries>> _candlesFromSource(
    String assetId,
    ChartInterval interval,
    int limit,
  ) {
    final key = '$assetId|${interval.name}|$limit';
    final running = _candleInFlight[key];
    if (running != null) return running;

    final source = _candleSourceFor(assetId);
    if (source == null) {
      return Future.value(
        Err(EmptyFailure('$assetId için mum verisi sağlayan kaynak yok.')),
      );
    }

    final future =
        source.fetchCandles(assetId: assetId, interval: interval, limit: limit);
    _candleInFlight[key] = future;
    future.whenComplete(() {
      if (identical(_candleInFlight[key], future)) _candleInFlight.remove(key);
    });
    return future;
  }

  /// Turev varlik icin bilesen mumlarindan hesaplanan seri.
  ///
  /// Boylece gram altin icin de gercek OHLC serisi gosterilebilir - sahte
  /// mum uretilmez, matematiksel olarak donusturulur.
  Future<Result<CandleSeries>> _deriveCandles(
    AssetDescriptor asset,
    ChartInterval interval,
    int limit,
    DateTime now,
  ) async {
    if (asset.parentIds.length >= 2) {
      // Orn. gram altin = ons x USD/TRY
      final first = await _candlesFromSource(asset.parentIds[0], interval, limit);
      final second = await _candlesFromSource(asset.parentIds[1], interval, limit);

      final seriesA = first.dataOrNull;
      final seriesB = second.dataOrNull;
      if (seriesA == null || seriesB == null) {
        return Err(first.failureOrNull ??
            second.failureOrNull ??
            const NetworkFailure());
      }

      final merged = _multiplySeries(
        assetId: asset.id,
        interval: interval,
        a: seriesA.candles,
        b: seriesB.candles,
        divider: MetalMath.gramsPerOunce,
        now: now,
      );
      if (merged.candles.isEmpty) {
        return const Err(EmptyFailure('Hesaplama için yeterli veri yok.'));
      }
      _candleCache['${asset.id}|${interval.name}|$limit'] =
          _CacheEntry(merged, now);
      return Success(merged);
    }

    // Tek bilesenli turev (orn. gram altin x ayar carpani)
    final parentId = asset.parentIds.isNotEmpty ? asset.parentIds.first : null;
    final parent = parentId == null ? null : AssetCatalog.byId(parentId);
    if (parent == null) {
      return const Err(BadRequestFailure('Hesaplama kaynağı bulunamadı.'));
    }

    final parentSeries =
        await getCandles(assetId: parent.id, interval: interval, limit: limit);
    final base = parentSeries.dataOrNull;
    if (base == null) {
      return Err(parentSeries.failureOrNull ?? const NetworkFailure());
    }

    final factor = _factorFor(asset.id);
    if (factor == null) {
      return const Err(BadRequestFailure('Hesaplama çarpanı tanımlı değil.'));
    }

    final converted = CandleSeries(
      assetId: asset.id,
      interval: interval,
      updatedAt: now,
      candles: [
        for (final c in base.candles)
          Candle(
            time: c.time,
            open: c.open * factor,
            high: c.high * factor,
            low: c.low * factor,
            close: c.close * factor,
            volume: c.volume,
          ),
      ],
    );
    _candleCache['${asset.id}|${interval.name}|$limit'] =
        _CacheEntry(converted, now);
    return Success(converted);
  }

  /// Iki seriyi birlestirir (carpar / boler).
  ///
  /// Iki kaynak **farkli borsa oturumlarinda** mum uretir. Yasam testi ile
  /// olculen gercek ornek:
  ///
  ///     GC=F     (ons altin) -> 2026-10-01 04:00 UTC
  ///     USDTRY=X (parite)    -> 2026-09-30 23:00 UTC   (ayni islem gunu)
  ///
  /// Birebir timestamp eslesmesi **hicbir zaman eslesmez**; takvim gunu ile
  /// esleme ise **bir gun kayar** (23:00 / 04:00 farki yuzunden). Bu nedenle
  /// **en yakin bar** eslestirmesi yapilir ve en fazla bir bar araligi
  /// toleransla kabul edilir.
  ///
  /// Elesme bulunamazsa seri **bos donulur** (sahte mum uretilmez).
  CandleSeries _multiplySeries({
    required String assetId,
    required ChartInterval interval,
    required List<Candle> a,
    required List<Candle> b,
    required double divider,
    required DateTime now,
  }) {
    final out = <Candle>[];
    final sortedB = [...b]..sort((x, y) => x.time.compareTo(y.time));
    final tolerance = _toleranceMs(interval);

    if (sortedB.isNotEmpty && tolerance != null) {
      for (final c in a) {
        final other = _nearest(sortedB, c.time);
        if (other == null || (other.time - c.time).abs() > tolerance) {
          continue;
        }
        final factor = _safeFactor(other, divider);
        if (factor == null) continue;
        out.add(_scale(c, factor));
      }
    }

    return CandleSeries(
      assetId: assetId,
      interval: interval,
      candles: out,
      updatedAt: now,
    );
  }

  /// Bir bar araligi kadar tolerans (ms).
  static int? _toleranceMs(ChartInterval interval) {
    switch (interval) {
      case ChartInterval.m1:
        return 60 * 1000;
      case ChartInterval.m5:
        return 5 * 60 * 1000;
      case ChartInterval.m15:
        return 15 * 60 * 1000;
      case ChartInterval.m30:
        return 30 * 60 * 1000;
      case ChartInterval.h1:
        return 60 * 60 * 1000;
      case ChartInterval.h4:
        return 4 * 60 * 60 * 1000;
      case ChartInterval.d1:
        return 24 * 60 * 60 * 1000;
      case ChartInterval.w1:
        return 7 * 24 * 60 * 60 * 1000;
      case ChartInterval.mo1:
        return 45 * 24 * 60 * 60 * 1000;
    }
  }

  static Candle? _nearest(List<Candle> sorted, int timeMs) {
    Candle? best;
    var bestDelta = 1 << 62;
    for (final c in sorted) {
      final d = (c.time - timeMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = c;
      }
    }
    return best;
  }

  static double? _safeFactor(Candle? other, double divider) {
    if (other == null) return null;
    final f = other.close / divider;
    return f.isFinite && f > 0 ? f : null;
  }

  static Candle _scale(Candle c, double factor) => Candle(
        time: c.time,
        open: c.open * factor,
        high: c.high * factor,
        low: c.low * factor,
        close: c.close * factor,
        volume: c.volume,
      );

  @override
  void invalidateQuotes() => _quoteCache.clear();

  @override
  void invalidateCandles() => _candleCache.clear();

  /// Tum onbellegi temizle (test/tek seferlik servis icin).
  ///
  /// UI "cekip-yenile" eylemi yalnizca [invalidateQuotes] cagirir; mum
  /// onbellekleri silinmez (fiyat tazelenmesi mini grafikleri ve acik
  /// grafigi gereksiz yere yeniden indirtmesin).
  void invalidateCache() {
    _quoteCache.clear();
    _candleCache.clear();
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.at);
  final T value;
  final DateTime at;
}
