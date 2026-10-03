import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/error/state_failure.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';

/// Secili kategori indeksi: 0=Borsa 1=Altın 2=Gümüş 3=Döviz 4=Fonlar
final marketCategoryProvider =
    NotifierProvider<MarketCategoryNotifier, int>(MarketCategoryNotifier.new);

class MarketCategoryNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// Piyasalar ekranindaki arama metni.
///
/// Bos dize = arama kapali (kategori listesi gosterilir). Arama **tum
/// katalog** uzerinden yapilir; kategori secimi arama sonucunu daraltmaz
/// (kullanici "USD/TRY" yazarken "Döviz" sekmesinde olmak zorunda degil).
final marketSearchProvider =
    NotifierProvider<MarketSearchNotifier, String>(MarketSearchNotifier.new);

class MarketSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// Kategoriye gore cekilen fiyat seti.
final marketQuotesProvider =
    AsyncNotifierProvider<MarketQuotesNotifier, Map<String, Quote>>(
  MarketQuotesNotifier.new,
);

class MarketQuotesNotifier extends AsyncNotifier<Map<String, Quote>> {
  Timer? _timer;

  @override
  Future<Map<String, Quote>> build() async {
    ref.onDispose(() => _timer?.cancel());

    // One donuldugunda zamanlayiciyi beklemeden tazele.
    ref.listen<bool>(appInForegroundProvider, (bool? prev, bool next) {
      if (next && prev == false) scheduleMicrotask(_silent);
    });

    _restartTimer();
    return _load();
  }

  /// Aralik saglayicidan gelir: piyasalar ekrani, varliklarin **destekledigi
  /// en hizli guncelleme araliginda** yenilenir (bkz.
  /// [MarketDataRepository.refreshInterval]).
  void _restartTimer() {
    _timer?.cancel();
    final cadence =
        ref.read(marketRepositoryProvider).refreshInterval(_currentIds());
    _timer = Timer.periodic(cadence, (_) => _silent());
  }

  Future<Map<String, Quote>> _load() async {
    final repo = ref.watch(marketRepositoryProvider);
    final res = await repo.getQuotes(_currentIds());
    return res.when(
      onSuccess: (map) => map,
      onFailure: (f) => throw StateFailure(f),
    );
  }

  /// Tum kategorilerde gezinirken tek seferde butun varliklari iste;
  /// boylece sekme degistirirken beklemek gerekmez.
  List<String> _currentIds() => AssetCatalog.all.map((a) => a.id).toList();

  Future<void> _silent() async {
    // Arka planda ag istegi yok (pil + gereksiz cagri).
    if (!ref.read(appInForegroundProvider)) return;
    final repo = ref.read(marketRepositoryProvider);
    final res = await repo.getQuotes(_currentIds());
    if (!ref.mounted) return;

    if (res case Success(data: final map)) {
      // Onceki degerler silinmez (bkz. [mergeQuotes]): saglayici bir sembolu
      // atlattiginda o varligin satiri kaybolmaz, bayat olarak kalir.
      final merged = mergeQuotes(state.value, map);
      if (merged.isNotEmpty) state = AsyncData(merged);
      return;
    }

    // Ag hatasi: son GERCEK veri ekranda kalir ama "guncel degil" olur.
    final prev = state.value;
    if (prev == null || prev.isEmpty) return;
    if (prev.values.every((q) => q.isStale)) return; // zaten isaretli
    state = AsyncData({
      for (final e in prev.entries) e.key: e.value.copyWith(isStale: true),
    });
  }

  /// Kullanici cekip yenilediginde cagrilir.
  ///
  /// `AsyncLoading` ile deger `null`'a cevrilmez: bu, tum satirlarin aninda
  /// kaybolmasina ve eksik donen yanitta kalici veri kaybina yol acardi.
  /// Onceki deger gorunur kalir, gelen sonuc [mergeQuotes] ile ustune yazilir.
  Future<void> refresh() async {
    // Yalnizca fiyat onbellegi tazelenir (mum onbellekleri korunur).
    ref.read(marketRepositoryProvider).invalidateQuotes();

    final prev = state.value;
    final res = await AsyncValue.guard(_load);
    if (!ref.mounted) return;

    final loaded = res.value;
    if (loaded != null) {
      state = AsyncData(mergeQuotes(prev, loaded));
      return;
    }
    if (prev == null || prev.isEmpty) {
      state = res; // Ilk acilis: hata gorunumu + Tekrar Dene.
      return;
    }
    state = AsyncData(mergeQuotes(prev, const <String, Quote>{}));
  }
}
