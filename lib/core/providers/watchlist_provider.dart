import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/asset_catalog.dart';
import 'app_providers.dart';

/// Kullanicinin takip ettigi varliklar (favoriler).
///
/// **Kalıcıdır**: uygulama kapanip acilinca kaybolmaz. Varsayilan olarak
/// one cikanlarla baslar; kullanici yildiz ile varlik ekleyip cikarabilir.
///
/// Mimari not: bu provider veri/UI ortak katmaninda durur; boylece hem ana
/// sayfa hem piyasalar hem varlik detay ayni listeyi paylasir (shared ->
/// features bagimliligi olusmaz).
final watchlistProvider =
    NotifierProvider<WatchlistNotifier, List<String>>(WatchlistNotifier.new);

class WatchlistNotifier extends Notifier<List<String>> {
  static const String _key = 'settings.watchlist';

  /// Takip listesi **senkron** okunur (build sirasinda `state` yazmak yerine
  /// ilk deger dogrudan donulur). Kayit yoksa one cikanlar varsayilandir.
  @override
  List<String> build() {
    try {
      final raw = ref.read(sharedPreferencesProvider).getString(_key);
      if (raw != null) {
        final ids = raw
            .split(',')
            .where((s) => s.isNotEmpty && AssetCatalog.byId(s) != null)
            .toList();
        // Kayit varsa (bosaltilmissa bile) kullanici tercihidir.
        return ids;
      }
    } catch (_) {
      // Tercih okunamazsa varsayilan liste kalir.
    }
    return AssetCatalog.featuredIds;
  }

  /// Varsayilan takip listesine (one cikanlar) don.
  void reset() {
    state = AssetCatalog.featuredIds;
    _save(state);
  }

  void toggle(String assetId) {
    // Tanimsiz varlik listeye eklenmez (uydurma varlik uretilmez).
    if (AssetCatalog.byId(assetId) == null) return;
    final next = state.contains(assetId)
        ? state.where((id) => id != assetId).toList()
        : [...state, assetId];
    state = next;
    _save(next);
  }

  void remove(String assetId) {
    if (!state.contains(assetId)) return;
    state = state.where((id) => id != assetId).toList();
    _save(state);
  }

  /// Varlik takip listesinde mi?
  bool contains(String assetId) => state.contains(assetId);

  Future<void> _save(List<String> ids) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_key, ids.join(','));
    } catch (_) {
      // Kayit basarisiz; bellekteki liste uygulama boyunca gecerli kalir.
    }
  }
}
