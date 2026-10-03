import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/error/state_failure.dart';
import '../../core/providers/app_providers.dart';
import '../../data/storage/portfolio_store.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/portfolio.dart';
import '../../domain/portfolio/portfolio_calculator.dart';

/// Portfoy islem listesi (kayitli + bellekte).
final portfolioProvider =
    NotifierProvider<PortfolioNotifier, List<PortfolioTransaction>>(
  PortfolioNotifier.new,
);

class PortfolioNotifier extends Notifier<List<PortfolioTransaction>> {
  PortfolioStore? _store;

  /// Kayitli islemler **build sirasinda senkron** okunur.
  ///
  /// Neden asenkron degil: `_load()` build icinde baslatilip sonrasi
  /// beklenmediginde (eski hali) iki sorun olusuyordu:
  ///   1. `state` yazimi `return const []` ile eziliyordu -> uygulama
  ///      her acilista "portfoy bos" gorunuyordu.
  ///   2. Ilk `add()` eski (bos) liste uzerine yapilip diske yazildiginda
  ///      kullaniciya ait **tum onceki islemler kalici olarak siliniyordu**.
  ///
  /// SharedPreferences bir kez baslatildiktan sonra senkron okuma
  /// yaptigindan yukleme build icinde dogrudan yapilabilir.
  @override
  List<PortfolioTransaction> build() {
    try {
      final store = PortfolioStore(ref.read(sharedPreferencesProvider));
      _store = store;
      return store.load();
    } catch (_) {
      // Depolama erisilemezse bos portfoy ile devam (kayit yok).
      return const [];
    }
  }

  Future<void> add(PortfolioTransaction t) async {
    if (!t.isValid) return;
    state = [...state, t];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((x) => x.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    final s = _store;
    if (s == null) return;
    await s.save(state);
  }
}

/// Portfoye eklenabilecek varliklar.
final portfolioAssetOptionsProvider =
    Provider<List<({String id, String name})>>((ref) {
  return [
    for (final a in AssetCatalog.all) (id: a.id, name: a.name),
  ];
});

/// Portfoyun hesaplanmis ozeti (guncel fiyatlarla).
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>((ref) async {
  final transactions = ref.watch(portfolioProvider);
  if (transactions.isEmpty) return PortfolioSummary.empty;

  final repo = ref.watch(marketRepositoryProvider);
  final ids = transactions.map((t) => t.assetId).toSet().toList();

  final res = await repo.getQuotes(ids);
  final quotes = res.dataOrNull;

  // Fiyatlar hic alinamadi (ag yok + onbellek bos): portfoyu **0,00 TL**
  // gostermek yanlis olurdu; kullanici "her sey dustu" sanir. Bunun yerine
  // hata gorunumu + Tekrar Dene gosterilir.
  //
  // Kisismi basari (bazi varliklarin fiyati var) normal calisir; eksik
  // varliklar hesaplayici tarafindan `hasMissingPrices` ile isaretlenir.
  if (quotes == null) {
    throw StateFailure(res.failureOrNull ?? const NetworkFailure());
  }

  return PortfolioCalculator.compute(
    transactions: transactions,
    names: {
      for (final a in AssetCatalog.all) a.id: a.name,
    },
    quotes: quotes,
  );
});
