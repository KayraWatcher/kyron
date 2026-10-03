import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/cache_policy.dart';
import '../../core/error/state_failure.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../charts/chart_types.dart';
import '../charts/heikin_ashi.dart';
import '../charts/indicator_engine.dart';

/// Acik olan varlik kimligi (detay sayfasi ustunden ayarlanir).
final assetIdProvider =
    NotifierProvider<AssetIdNotifier, String?>(AssetIdNotifier.new);

class AssetIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String id) => state = id;
}

/// Varlik detayindaki secili zaman dilimi.
final chartIntervalProvider =
    NotifierProvider<ChartIntervalNotifier, ChartInterval>(
  ChartIntervalNotifier.new,
);

class ChartIntervalNotifier extends Notifier<ChartInterval> {
  @override
  ChartInterval build() => ChartInterval.d1;

  void select(ChartInterval i) => state = i;
}

/// Varlik detayindaki grafik tipi.
final chartTypeProvider =
    NotifierProvider<ChartTypeNotifier, ChartType>(ChartTypeNotifier.new);

class ChartTypeNotifier extends Notifier<ChartType> {
  @override
  ChartType build() => ChartType.candlestick;

  void select(ChartType t) => state = t;
}

/// Aktif gosterge listesi.
final activeIndicatorsProvider =
    NotifierProvider<ActiveIndicatorsNotifier, List<IndicatorConfig>>(
  ActiveIndicatorsNotifier.new,
);

class ActiveIndicatorsNotifier extends Notifier<List<IndicatorConfig>> {
  @override
  List<IndicatorConfig> build() => const [];

  void add(IndicatorConfig cfg) {
    if (state.any((e) => e.id == cfg.id)) return;
    state = [...state, cfg];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  void toggle(String id, bool visible) {
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(visible: visible) else e,
    ];
  }

  void setParam(String id, String key, double value) {
    state = [
      for (final e in state)
        if (e.id == id)
          e.copyWith(params: {...e.params, key: value})
        else
          e,
    ];
  }

  void clear() => state = const [];
}

/// Varligin guncel fiyati - **`Data Provider -> Stream -> Repository -> UI`**.
///
/// Akis saglayicinin destekledigi en hizli aralikta kendini tazeler:
///
///  * Basari     -> yeni fiyat yayinlanir (fiyat, alis/satis, % ayni anda).
///  * Ag koparsa -> **son gercek veri korunur**, `isStale` isaretiyle
///    "guncel degil" gosterilir ve akis **kendiliginden yeniden dener**.
///  * Ilk istekte veri yoksa akis hata yayar; UI "Tekrar Dene" gosterir.
///
/// Arka planda zamanlayici ayakta kalir ama **ag istegi atmaz**; uygulama
/// one dondugunde akis yeniden kurulur ve **hemen bir kez** tazelenir.
///
/// Hiz: kullanici detay ekraninda tek bir varlik izler; bu yuzden listelere
/// gore cok daha kisa bir ritim kullanilir (`focusedQuoteRefreshInterval`).
/// Saglayici hata alirsa repository ritmi ustel olarak uzatir.
final assetQuoteProvider = StreamProvider.autoDispose.family<Quote, String>(
  (ref, assetId) {
    final repo = ref.watch(marketRepositoryProvider);

    ref.listen<bool>(appInForegroundProvider, (bool? prev, bool next) {
      if (next && prev == false) ref.invalidateSelf();
    });

    return repo.watchQuotes(
      [assetId],
      interval: CachePolicy.focusedQuoteRefreshInterval,
      isActive: () => ref.read(appInForegroundProvider),
    ).where((m) => m.containsKey(assetId)).map((m) => m[assetId]!);
  },
);

/// Capraz imlecin (uzun basma) sectigi mum - **ustteki ana fiyat onizlemesi**.
///
///  * `null`  -> imlec kapali; ust baslik **canli** fiyati gosterir.
///  * mum     -> ust baslik o mumun kapanisini ve **tarihini** gosterir;
///    yani grafikte gecmise kaydirildiginda ana fiyat da o tarihe gecer.
///
/// Tazelik etiketi bu modda "Gecikmeli/Canli" degil **"Geçmiş mum"** olur;
/// guncel fiyat da ayrica "Guncel:" onekiyle altta gosterilir, boylece
/// tarihsel deger ile anlik deger karistirilmaz.
///
/// Yalnizca imlec **bir mumdan digerine** gectiginde yazilir; imlec ayni
/// mumun icinde hareket ederken ust baslik gereksiz yere yeniden kurulmaz.
///
/// `autoDispose` + varlik anahtari: detay sayfasi kapatildiginda kimse
/// izlemez olur ve deger sifirlanir - bir sonraki acilista baslik
/// yanlislikla eski bir tarihsel fiyat gostermez.
final crosshairCandleProvider = NotifierProvider.autoDispose
    .family<CrosshairPickNotifier, Candle?, String>(CrosshairPickNotifier.new);

class CrosshairPickNotifier extends Notifier<Candle?> {
  CrosshairPickNotifier(this.assetId);

  /// Bu imlecin bagli oldugu varlik (family argumani) - yalnizca ayni
  /// varlik icin okunur; baska sayfanin eski degeri yanlis gosterilmez.
  final String assetId;

  @override
  Candle? build() => null;

  /// Imlec mumu `candle` olarak isaretler; `null` imlecin kalktigi anlamina
  /// gelir (ust baslik canli moda doner).
  ///
  /// `ref.mounted` kontrolu: sayfa kapanirken eski bir isaretlemeyi
  /// guvenli sekilde sifirlamak icin.
  void pick(Candle? candle) {
    if (!ref.mounted) return;
    state = candle;
  }
}

// -----------------------------------------------------------------------------
// Saf cozumleme (test edilebilir)
// -----------------------------------------------------------------------------

/// Capraz imlecin indeksini serideki **mumun kendisine** cevirir.
///
///  * `index` null veya seri bos  -> `null` (imlec kapali / veri yok).
///  * indeks serinin disinda      -> **sikistirilir** (clamped); serinin
///    disinda bir mum **uydurulmaz**, varolan ilk/son mum gosterilir.
Candle? resolveCrosshairCandle(List<Candle> candles, int? index) {
  if (index == null || candles.isEmpty) return null;
  if (index < 0) return candles.first;
  if (index > candles.length - 1) return candles.last;
  return candles[index];
}

/// Imlec bir **farkli muma** gecti mi?
///
/// Ayni mumun icinde imlecin gezmeye devam etmesi ust basligi yeniden
/// kurmaz (Faz F: gereksiz yeniden kurulum yok). `null` <- `null` gecisi de
/// degisiklik sayilmaz (zaten canli moda geçilmistir).
bool crosshairChanged(Candle? prev, Candle? next) {
  if (prev == null || next == null) return !identical(prev, next);
  return prev.time != next.time || prev.close != next.close;
}

/// Secili araliktaki mum serisi.
///
/// Seri 3 dakikada bir sessizce yenilenir ki **olusan bar** (son mum)
/// kapanisina dogru guncellensin; arka planda istek atilmaz.
final assetCandlesProvider = FutureProvider.autoDispose
    .family<CandleSeries, (String, ChartInterval)>((ref, arg) async {
  final (assetId, interval) = arg;

  Future<CandleSeries> load() async {
    final repo = ref.read(marketRepositoryProvider);
    final res = await repo.getCandles(
      assetId: assetId,
      interval: interval,
      limit: 300,
    );
    return res.when(
      onSuccess: (s) => s,
      onFailure: (f) => throw StateFailure(f),
    );
  }

  Future<void> silentRefresh() async {
    if (!ref.mounted) return;
    if (!ref.read(appInForegroundProvider)) return;
    ref.invalidateSelf();
  }

  ref.listen<bool>(appInForegroundProvider, (bool? prev, bool next) {
    if (next && prev == false) silentRefresh();
  });

  final timer = Timer.periodic(CachePolicy.candleTtl, (_) => silentRefresh());
  ref.onDispose(timer.cancel);

  return load();
});

/// Hesaplanan gosterge ciktilari.
///
/// Mum serisi bos ise bos donulur; **uydurma gosterge uretilmez**.
///
/// Gostergeler her zaman **ekranda goruntulenen seri** uzerinden hesaplanir:
/// Heikin Ashi seciliyken SMA/RSI gibi cizgiler HA mumlariyla ayni degerden
/// turetilir (aksi halde cizgi mumlarin ustunde tutmaz, "bozuk gosterge"
/// gorunumu olusur). Heikin Ashi bir **donusumdur**: gercek seri degismez,
/// yalnizca gorsellestirmede kullanilir.
final computedIndicatorsProvider = Provider.autoDispose
    .family<List<ComputedIndicator>, (String, ChartInterval)>((ref, arg) {
  final configs = ref.watch(activeIndicatorsProvider);
  if (configs.isEmpty) return const [];
  final series = ref.watch(assetCandlesProvider(arg));
  final candles = series.value?.candles;
  if (candles == null || candles.isEmpty) return const [];
  final displayed =
      ref.watch(chartTypeProvider) == ChartType.heikinAshi
          ? HeikinAshi.convert(candles)
          : candles;
  return IndicatorEngine.compute(displayed, configs);
});

/// Varlik kimligi / adi / birimi.
final assetDescriptorProvider =
    Provider.autoDispose.family((ref, String id) => AssetCatalog.byId(id));
