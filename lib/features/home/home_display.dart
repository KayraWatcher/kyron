import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';

/// Ana sayfa "Piyasalar" listesi filtresi.
enum HomeFilter {
  onecikanlar('Öne çıkanlar'),
  tumu('Tümü'),
  borsa('Borsa'),
  altin('Altın'),
  gumus('Gümüş'),
  doviz('Döviz'),
  fon('Fonlar'),
  takip('Takip edilenler');

  const HomeFilter(this.label);

  /// UI'da gosterilen etiket.
  final String label;
}

/// Ana sayfa "Piyasalar" listesi siralama alani.
enum HomeSortField {
  varsayilan('Varsayılan'),
  fiyat('Fiyat'),
  degisimYuzde('Günlük değişim %'),
  degisimTutar('Değişim miktarı'),
  alis('Alış'),
  satis('Satış');

  const HomeSortField(this.label);

  final String label;
}

/// Ana sayfa varlik gorunumu: izgara (2 sutun) veya liste (1 sutun).
enum HomeViewMode {
  grid('Izgara'),
  list('Liste');

  const HomeViewMode(this.label);

  final String label;
}

/// Filtre + siralama + gorunum durumu.
class HomeDisplayState {
  const HomeDisplayState({
    this.filter = HomeFilter.onecikanlar,
    this.sort = HomeSortField.varsayilan,
    this.ascending = true,
    this.pinned = AssetCatalog.featuredIds,
    this.view = HomeViewMode.grid,
  });

  final HomeFilter filter;
  final HomeSortField sort;

  /// `true` = artan (kucukten buyuge), `false` = azalan (buyukten kucuge).
  final bool ascending;

  /// "Öne çıkanlar" filtresinde **kullaniciya ait** sira.
  ///
  /// Kullanici varlik ekleyip cikarabilir, sirasini degistirebilir;
  /// tercih kalıcıdır (uygulama kapanip acilinca kaybolmaz).
  final List<String> pinned;

  /// Izgara / liste gorunum tercihi.
  final HomeViewMode view;

  /// Varsayilan davranisa donuldu mu? (buton rozeti icin)
  bool get isDefault =>
      filter == HomeFilter.onecikanlar &&
      sort == HomeSortField.varsayilan &&
      ascending &&
      listEquals(pinned, AssetCatalog.featuredIds) &&
      view == HomeViewMode.grid;

  HomeDisplayState copyWith({
    HomeFilter? filter,
    HomeSortField? sort,
    bool? ascending,
    List<String>? pinned,
    HomeViewMode? view,
  }) =>
      HomeDisplayState(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
        pinned: pinned ?? this.pinned,
        view: view ?? this.view,
      );
}

final homeDisplayProvider =
    NotifierProvider<HomeDisplayNotifier, HomeDisplayState>(
  HomeDisplayNotifier.new,
);

class HomeDisplayNotifier extends Notifier<HomeDisplayState> {
  /// Ana sayfa filtre/siralama tercihi. `filter|sort|yon` biciminde saklanir.
  ///
  /// Kalici olmali: kullanici "Altin + Fiyat azalan" sectiyse uygulama
  /// her acilista varsayilana donmemeli (cihaz testinde gozlemlenen hata).
  static const String prefsKey = 'home_display.v1';

  /// One cikanlar sirasi (virgulle) + gorunum tercihi. Ayr anahtarda
  /// tutulur ki eski `filter|sort|yon` bicimi bozulmasin.
  static const String pinnedKey = 'home_display.pinned';
  static const String viewKey = 'home_display.view';

  @override
  HomeDisplayState build() => _restore();

  HomeDisplayState _restore() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final raw = prefs.getString(prefsKey);
      final base = raw == null
          ? const HomeDisplayState()
          : _parseBase(raw);

      final pinned = _parsePinned(prefs.getString(pinnedKey));
      final view = switch (prefs.getString(viewKey)) {
        'list' => HomeViewMode.list,
        _ => HomeViewMode.grid,
      };

      return base.copyWith(pinned: pinned, view: view);
    } catch (_) {
      // Prefs yoksa (testler) veya bozuksa: varsayilan.
      return const HomeDisplayState();
    }
  }

  HomeDisplayState _parseBase(String raw) {
    final parts = raw.split('|');
    if (parts.length != 3) return const HomeDisplayState();

    HomeFilter filter = HomeFilter.onecikanlar;
    for (final f in HomeFilter.values) {
      if (f.name == parts[0]) filter = f;
    }
    HomeSortField sort = HomeSortField.varsayilan;
    for (final s in HomeSortField.values) {
      if (s.name == parts[1]) sort = s;
    }
    return HomeDisplayState(
      filter: filter,
      sort: sort,
      ascending: parts[2] != '0',
    );
  }

  /// Kayitli one cikan listesi; tanimsiz varliklar elenir.
  ///
  /// Kayit yoksa varsayilan one cikanlar. Kayit varsa (bosluk dahil) o
  /// kullanici tercihidir: kullanici hepsini cikarmissa liste bos kalir
  /// (bos liste gercek bir tercihtir - uydurma varlik eklenmez).
  List<String> _parsePinned(String? raw) {
    if (raw == null) return AssetCatalog.featuredIds;
    return raw
        .split(',')
        .where((s) => s.isNotEmpty && AssetCatalog.byId(s) != null)
        .toList();
  }

  void _persist() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString(
        prefsKey,
        '${state.filter.name}|${state.sort.name}|'
        '${state.ascending ? 1 : 0}',
      );
      prefs.setString(pinnedKey, state.pinned.join(','));
      prefs.setString(viewKey, state.view.name);
    } catch (_) {
      // Kayit basarisizsa tercih bellekte kalir; uygulama calismaya devam eder.
    }
  }

  void setFilter(HomeFilter f) {
    if (state.filter == f) return;
    state = state.copyWith(filter: f);
    _persist();
  }

  void setSort(HomeSortField s, {required bool ascending}) {
    if (state.sort == s && state.ascending == ascending) return;
    state = state.copyWith(sort: s, ascending: ascending);
    _persist();
  }

  void setView(HomeViewMode v) {
    if (state.view == v) return;
    state = state.copyWith(view: v);
    _persist();
  }

  // ---------------------------------------------------------------------------
  // ONE CIKANLAR (ekle / cikar / sirala)
  // ---------------------------------------------------------------------------

  void pinAdd(String assetId) {
    if (AssetCatalog.byId(assetId) == null) return;
    if (state.pinned.contains(assetId)) return;
    state = state.copyWith(pinned: [...state.pinned, assetId]);
    _persist();
  }

  void pinRemove(String assetId) {
    if (!state.pinned.contains(assetId)) return;
    state = state.copyWith(
      pinned: state.pinned.where((id) => id != assetId).toList(),
    );
    _persist();
  }

  /// [assetId]'yi [delta] kadar yukari/asagi tasi (+1 asagi, -1 yukari).
  void pinMove(String assetId, int delta) {
    final list = [...state.pinned];
    final from = list.indexOf(assetId);
    if (from < 0) return;
    final to = from + delta;
    if (to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    state = state.copyWith(pinned: list);
    _persist();
  }

  /// Henuz one cikan olmayan katalog varliklari (ekleme listesi).
  List<String> get pinCandidates => [
        for (final a in AssetCatalog.all)
          if (!state.pinned.contains(a.id)) a.id,
      ];

  /// "En çok yükselen" / "En çok düşen" kisayolu.
  void setQuickRising({required bool rising}) =>
      setSort(HomeSortField.degisimYuzde, ascending: !rising);

  void reset() {
    state = const HomeDisplayState();
    _persist();
  }
}

/// Filtre + siralama - **saf fonksiyon** (birim testi icin).
///
/// Kurallar:
///  * Verisi olmayan varlik listeye girmez (UI'da "—" karti uretilmez).
///  * Eksik/alansiz deger **sona** konur; yon ne olursa olsun sonda kalir
///    (yok deger 0 kabul edilmez, uydurma deger uretilmez).
///  * Varsayilan sira, katalog/takip listesinin kendi sirasidir.
///  * Esitlikte katalog sirasi korunur ki liste ziplamasin.
List<String> applyHomeDisplay({
  required List<String> featured,
  required List<AssetDescriptor> catalog,
  required List<String> watchlist,
  required Map<String, Quote> quotes,
  required HomeDisplayState display,
}) {
  final base = <String>[
    ...switch (display.filter) {
      HomeFilter.onecikanlar => featured,
      HomeFilter.tumu => [for (final a in catalog) a.id],
      HomeFilter.takip => watchlist,
      HomeFilter.borsa =>
        [for (final a in catalog) if (a.category == AssetCategory.borsa) a.id],
      HomeFilter.altin =>
        [for (final a in catalog) if (a.category == AssetCategory.altin) a.id],
      HomeFilter.gumus =>
        [for (final a in catalog) if (a.category == AssetCategory.gumus) a.id],
      HomeFilter.doviz =>
        [for (final a in catalog) if (a.category == AssetCategory.doviz) a.id],
      HomeFilter.fon =>
        [for (final a in catalog) if (a.category == AssetCategory.fon) a.id],
    },
  ].where(quotes.containsKey).toList();

  if (display.sort == HomeSortField.varsayilan) return base;

  double? valueOf(Quote? q) {
    if (q == null) return null;
    final v = switch (display.sort) {
      HomeSortField.fiyat => q.price,
      HomeSortField.degisimYuzde => q.effectiveChangePercent,
      HomeSortField.degisimTutar => q.effectiveChange,
      HomeSortField.alis => q.bid,
      HomeSortField.satis => q.ask,
      HomeSortField.varsayilan => null,
    };
    if (v == null || !v.isFinite) return null;
    return v;
  }

  // Katalog sirasina gore eslestirme (esitlikte karar verir).
  final order = <String, int>{
    for (var i = 0; i < base.length; i++) base[i]: i,
  };

  return [...base]..sort((a, b) {
      final va = valueOf(quotes[a]);
      final vb = valueOf(quotes[b]);

      // Eksik deger her yonde sonda kalir; ikisi de eksikse katalog
      // sirasina duser (List.sort kararli degildir - sipars bozulmasin).
      if (va == null && vb == null) {
        return (order[a] ?? 0).compareTo(order[b] ?? 0);
      }
      if (va == null) return 1;
      if (vb == null) return -1;

      final cmp = va.compareTo(vb);
      if (cmp != 0) return display.ascending ? cmp : -cmp;

      return (order[a] ?? 0).compareTo(order[b] ?? 0);
    });
}
