import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/error/state_failure.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';

// Takip listesi artik paylasilan katmanda (shared -> features bagimliligi
// olusmasin diye): hem ana sayfa hem piyasalar hem varlik detay ayni
// provider'i kullanir.
export '../../core/providers/watchlist_provider.dart'
    show watchlistProvider, WatchlistNotifier;

/// Ana sayfa one cikan varliklarin guncel fiyatlarini tutar.
///
/// Otomatik yenileme **saglayicinin destekledigi aralikla** calisir
/// (`MarketDataRepository.refreshInterval`); uygulama arka planda oldugunda
/// zamanlayici istek atmaz ve one donuldugunde **hemen bir kez** yenilenir.
final homeQuotesProvider =
    AsyncNotifierProvider<HomeQuotesNotifier, Map<String, Quote>>(
  HomeQuotesNotifier.new,
);

class HomeQuotesNotifier extends AsyncNotifier<Map<String, Quote>> {
  Timer? _timer;

  /// Ana sayfanin fiyat istedigi set.
  ///
  /// **Neden tum katalog?** Filtreler (Tümü/Altın/Döviz/...) katalogdan
  /// uretilir, sonra "fiyati olmayan elenir" kurali uygulanir. Eski hali
  /// yalnizca 7 one cikan varligi istedigi icin "Tümü" 17 yerine 7 kart,
  /// "Altın" 8 yerine 2 kart gosteriyordu.
  ///
  /// **Maliyet neredeyse ayni:** dogrudan Yahoo sembolleri (BIST100/30,
  /// ons altin, ons gumus) zaten one cikanlarin icinde; TCMB tek XML
  /// istegiyle 5 kuru birden doner; kalan varliklar **yerelde hesaplanir**.
  List<String> _ids() => [for (final a in AssetCatalog.all) a.id];

  @override
  Future<Map<String, Quote>> build() async {
    ref.onDispose(() => _timer?.cancel());

    // One donuldugunde zamanlayiciyi beklemeden tazele.
    ref.listen<bool>(appInForegroundProvider, (bool? prev, bool next) {
      if (next && prev == false) scheduleMicrotask(_silentRefresh);
    });

    _restartTimer();
    return _load();
  }

  /// Aralik saglayicidan gelir; sabit bir deger kodda tutulmaz.
  void _restartTimer() {
    _timer?.cancel();
    final cadence = ref
        .read(marketRepositoryProvider)
        .refreshInterval(_ids());
    _timer = Timer.periodic(cadence, (_) => _silentRefresh());
  }

  Future<Map<String, Quote>> _load() async {
    final repo = ref.watch(marketRepositoryProvider);
    final res = await repo.getQuotes(_ids());
    return res.when(
      onSuccess: (map) => map,
      onFailure: (f) => throw StateFailure(f),
    );
  }

  /// Zamanlayici tetiklemesinde hatayi state'i bozmadan uygula.
  ///
  /// **Not (Aşama 16 duzeltmesi):** Onceki kosul `!ref.mounted` idi ve bu
  /// nedenle sessiz yenileme **hicbir zaman calismazdi** (yalnizca provider
  /// hala yasarken yazim yapilabilir).
  Future<void> _silentRefresh() async {
    // Arka planda ag istegi yok (pil + gereksiz cagri).
    if (!ref.read(appInForegroundProvider)) return;
    final repo = ref.read(marketRepositoryProvider);
    final res = await repo.getQuotes(_ids());
    if (!ref.mounted) return;

    if (res case Success(data: final map)) {
      // Yeni map'i oncekiyle birlestir (bkz. [mergeQuotes]):
      // saglayici GC=F / SI=F'yi gecici olarak atlattiginda kartlar
      // kaybolmaz, son degeriyle bayat olarak ekranda kalir.
      final merged = mergeQuotes(state.value, map);
      if (merged.isNotEmpty) state = AsyncData(merged);
      return;
    }

    // Ag hatasi: son GERCEK veri ekranda kalir ama "guncel degil" olur.
    // Zamanlayici kendiliginden yeniden dener (otomatik baglanti kurulumu).
    final prev = state.value;
    if (prev == null || prev.isEmpty) return;
    if (prev.values.every((q) => q.isStale)) return; // zaten isaretli
    state = AsyncData({
      for (final e in prev.entries) e.key: e.value.copyWith(isStale: true),
    });
  }

  /// Kullanici cekip yenilediginde (RefreshIndicator / Tekrar Dene) cagrilir.
  ///
  /// **Neden `AsyncLoading` kullanilmiyor?** `state = const AsyncLoading()`
  /// degeri `null`'a cevirir; `toViewState` bu durumda tum grid'i spinner'a
  /// cevirir (kartlar aninda kaybolur) ve hemen ardindan gelen **eksik**
  /// yanitta eksik id'ler kalici olarak haritadan dusmus olur. Boylece
  /// Ons Altin / Ons Gumus kartlari silinir ve saglayici sembol
  /// dondurene kadar ekranda gorunmez.
  ///
  /// Bunun yerine onceki deger **gorunur kalir**; gelen sonuc
  /// [mergeQuotes] ile ustune yazilir, gelmeyen id'ler bayat olarak
  /// isaretlenir. Yalnizca ilk acilista (henuz veri yokken) hata
  /// gorunumu gosterilir.
  Future<void> refresh() async {
    // Onbellegi zorla tazele: cekip-yenile GERCEKTEN yeni istek atsin.
    // Yalnizca fiyat onbellegi temizlenir - mum/mini grafik onbellekleri
    // korunur ki tek bir yenileme tum grafigi yeniden indirmesin.
    ref.read(marketRepositoryProvider).invalidateQuotes();

    final prev = state.value;
    final res = await AsyncValue.guard(_load);
    if (!ref.mounted) return;

    final loaded = res.value;
    if (loaded != null) {
      state = AsyncData(mergeQuotes(prev, loaded));
      return;
    }

    // Yukleme basarisiz: varsa onceki GERCEK veri ekranda kalsin.
    if (prev == null || prev.isEmpty) {
      state = res; // Ilk acilis: hata gorunumu + Tekrar Dene.
      return;
    }
    state = AsyncData(mergeQuotes(prev, const <String, Quote>{}));
  }
}
