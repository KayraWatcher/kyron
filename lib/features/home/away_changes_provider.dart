import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../domain/repositories/market_data_repository.dart';

/// "Sen Yokken Ne Oldu?" öğesi.
class AwayChangeItem {
  const AwayChangeItem({
    required this.assetId,
    required this.name,
    required this.symbol,
    required this.changePercent,
    required this.currentPrice,
    required this.previousPrice,
  });

  final String assetId;
  final String name;
  final String symbol;
  final double changePercent;
  final double currentPrice;
  final double previousPrice;
}

/// "Sen Yokken Ne Oldu?" verisi.
class AwayChangesData {
  const AwayChangesData({
    required this.items,
    this.lastVisit,
    this.errorMessage,
  });

  final List<AwayChangeItem> items;
  final DateTime? lastVisit;
  final String? errorMessage;

  factory AwayChangesData.empty({DateTime? lastVisit, String? errorMessage}) =>
      AwayChangesData(items: [], lastVisit: lastVisit, errorMessage: errorMessage);

  bool get hasData => items.isNotEmpty;
}

/// "Sen Yokken Ne Oldu?" bolumunde gosterilecek varliklarin **azami** sayisi.
///
/// Gereksiz yere kalabaliklasmamasi icin 4-6 araliginin ust siniri: 6.
const int awaySelectionMax = 6;

/// Ilk kurulumda (kayit yoksa) gosterilecek varliklar.
const List<String> awaySelectionDefaults = [
  AssetCatalog.gramAltinId,
  AssetCatalog.ceyrekAltinId,
];

/// "Sen Yokken Ne Oldu?" bolumunde gosterilecek varliklar ve **sirasi**.
///
/// * Secim yalnizca uygulamanin mevcut [AssetCatalog] varliklarindan yapilir
///   (uydma/fake asset eklenemez).
/// * Varsayilan: Gram Altin + Ceyrek Altin (ilk kurulumda kayit yoksa).
/// * Eklemek/kaldirmak/siralamak SharedPreferences'da saklanir; uygulama
///   yeniden acilsa da korunur.
/// * Bolum yalnizca **hangi assetlerin gosterilecegini** belirler: fiyat
///   hesaplama, veri cekme ve hareket analizi [awayChangesProvider] aynen
///   calismaya devam eder.
final awaySelectionProvider =
    NotifierProvider<AwaySelectionNotifier, List<String>>(
  AwaySelectionNotifier.new,
);

class AwaySelectionNotifier extends Notifier<List<String>> {
  /// Kalici secim: virgulle ayrilmis canonical varlik id'leri.
  static const String prefsKey = 'away_selection.v1';

  @override
  List<String> build() => _restore();

  /// Kayit yoksa varsayilan (Gram + Ceyrek). Kayitli olmayan / tanimsiz
  /// id'ler elenir; uydurma varlik listeye girmez.
  List<String> _restore() {
    try {
      final raw = ref.read(sharedPreferencesProvider).getString(prefsKey);
      if (raw == null) return List<String>.of(awaySelectionDefaults);

      // Kullanici tum varliklari silmisse bu gecerli bir tercidir
      // (kayit VAR, bos); bolum "Düzenle" ile geri doldurulabilir.
      if (raw.trim().isEmpty) return <String>[];

      final ids = <String>[];
      for (final part in raw.split(',')) {
        final id = part.trim();
        if (id.isEmpty) continue;
        if (AssetCatalog.byId(id) == null) continue;
        if (ids.contains(id)) continue;
        ids.add(id);
      }
      // Tamami gecersiz kayit: bozuk veri varsayilana duser (uydurma secim
      // yapilmaz).
      if (ids.isEmpty) return List<String>.of(awaySelectionDefaults);
      return ids.take(awaySelectionMax).toList();
    } catch (_) {
      // Prefs yoksa (test) veya okunamazsa: varsayilan.
      return List<String>.of(awaySelectionDefaults);
    }
  }

  void _persist() {
    try {
      ref.read(sharedPreferencesProvider).setString(prefsKey, state.join(','));
    } catch (_) {
      // Kayit basarisizsa tercih bellekte kalir; uygulama calismaya devam eder.
    }
  }

  /// Varsayilan secimde miyiz? (Sifirla butonu icin)
  bool get isDefault {
    if (state.length != awaySelectionDefaults.length) return false;
    for (var i = 0; i < state.length; i++) {
      if (state[i] != awaySelectionDefaults[i]) return false;
    }
    return true;
  }

  /// Eklenebilecek varliklar (katalogda olup secimde olmayanlar).
  List<String> get candidates => [
        for (final a in AssetCatalog.all)
          if (!state.contains(a.id)) a.id,
      ];

  /// Secime varlik ekler. Tanimsiz varlik, tekrar ve ust sinir disi sessizce
  /// yok sayilir (uyduma varlik uretilmez, sinir asilmaz).
  void add(String assetId) {
    if (AssetCatalog.byId(assetId) == null) return;
    if (state.contains(assetId)) return;
    if (state.length >= awaySelectionMax) return;
    state = <String>[...state, assetId];
    _persist();
  }

  /// Secimden varlik kaldirir (minimum sinir yok: bolum bos kalabilir,
  /// "Düzenle" ile geri eklenebilir).
  void remove(String assetId) {
    if (!state.contains(assetId)) return;
    state = state.where((id) => id != assetId).toList();
    _persist();
  }

  /// [assetId]'yi [delta] kadar yukari/asagi tasi (+1 asagi, -1 yukari).
  void move(String assetId, int delta) {
    final list = [...state];
    final from = list.indexOf(assetId);
    if (from < 0) return;
    final to = from + delta;
    if (to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    state = list;
    _persist();
  }

  /// Varsayilana don (Gram Altin + Ceyrek Altin).
  void reset() {
    state = List<String>.of(awaySelectionDefaults);
    _persist();
  }
}

/// Secime gore bolum ogelerini **filtreler ve sirlar** - saf fonksiyon
/// (birim testi icin).
///
/// * Gosterim sirasi kullanici seciminin sirasidir (siralama tercihi korunur).
/// * Secimde olmayan varliklar gosterilmez; verisi gelmeyen secili varlik
///   zaten ogelerde yer almaz (uydurma veri uretilmez).
List<AwayChangeItem> applyAwaySelection({
  required List<AwayChangeItem> items,
  required List<String> selection,
}) {
  final byId = <String, AwayChangeItem>{
    for (final item in items) item.assetId: item,
  };
  final out = <AwayChangeItem>[];
  final seen = <String>{};
  for (final id in selection) {
    final item = byId[id];
    if (item != null && seen.add(id)) out.add(item);
  }
  return out;
}

/// Son ziyaretten bu yana en çok değişen varlıkları hesaplar.
///
/// Persistence ile son ziyaret zamanını ve fiyatlarını saklar.
/// İlk açılışta veri yoksa boş döner.
///
/// **Not:** Ogreler tum katalog icin hesaplanir; bolumun gosterdigi
/// varliklar [applyAwaySelection] ile secime gore daraltilir. Boylece
/// kullanici bir varligi sonradan sectiginde veri hazir olur ve secim
/// degisikligi veri saglayiciyi yeniden calistirmaz (ziyaret temeli
/// korunur). Cekilen varlik seti secime bagli degildir.
final awayChangesProvider = FutureProvider.autoDispose<AwayChangesData>((
  ref,
) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = ref.watch(marketRepositoryProvider);

  // Son ziyaret zamanını ve fiyatlarını oku
  final lastVisitMs = prefs?.getInt('away_last_visit_ms');
  final lastPricesJson = prefs?.getString('away_last_prices');

  final now = DateTime.now();

  // Eğer hiç ziyaret yoksa boş dön (fake veri üretme)
  if (lastVisitMs == null || lastPricesJson == null) {
    // Bu seferki fiyatları kaydet
    await _saveCurrentState(prefs, now, {});
    return AwayChangesData.empty(lastVisit: now);
  }

  final lastVisit = DateTime.fromMillisecondsSinceEpoch(lastVisitMs);
  final Map<String, double> lastPrices = {};

  try {
    final map = Map<String, dynamic>.from(
        lastPricesJson.isEmpty ? {} : _parseJson(lastPricesJson));
    map.forEach((k, v) => lastPrices[k] = (v as num).toDouble());
  } catch (_) {
    // Parse hatası: sıfırla
    await _saveCurrentState(prefs, now, {});
    return AwayChangesData.empty(lastVisit: now);
  }

  // Guncel fiyatlari getir: tum katalog (Ana Sayfa zaten ayni katalogu
  // cekiyor - bkz. HomeQuotesNotifier._ids). Bolumun gosterdigi set secime
  // bagli DEGIL; boylece secim degisikligi bu hesaplamayi yeniden
  // calistirip "son ziyaret" temelini sifirlamaz ve sonradan secilen bir
  // varligin verisi (mevcut sistemden ayni kaynak) hazir olur.
  final fetchIds = [for (final a in AssetCatalog.all) a.id];
  final quotesResult = await repo.getQuotes(fetchIds);

  return quotesResult.when(
    onSuccess: (quotesMap) {
      final changes = <AwayChangeItem>[];

      for (final entry in quotesMap.entries) {
        final assetId = entry.key;
        final quote = entry.value;
        final currentPrice = quote.price;

        if (currentPrice == null || !currentPrice.isFinite) continue;

        final lastPrice = lastPrices[assetId];
        if (lastPrice == null || !lastPrice.isFinite || lastPrice <= 0) continue;

        final changePercent = ((currentPrice - lastPrice) / lastPrice) * 100;

        // Sadece anlamlı değişimleri al (> 0.05%)
        if (changePercent.abs() < 0.05) continue;

        final asset = AssetCatalog.byId(assetId);
        if (asset == null) continue;

        changes.add(AwayChangeItem(
          assetId: assetId,
          name: asset.name,
          symbol: asset.symbol,
          changePercent: changePercent,
          currentPrice: currentPrice,
          previousPrice: lastPrice,
        ));
      }

      // Mutlak değişim büyüklüğüne göre sırala (gorunum sirasi secte
      // applyAwaySelection ile uygulanir; ust sinir artik secimdir - en fazla
      // awaySelectionMax satir gosterilir, take siniri kaldirildi).
      changes.sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));

      // Yeni fiyatları ve zamanı kaydet (fiyati olmayan kayit atlanir -
      // katalog genislemesinde null deger yuzunden carpma olmaz).
      final newPrices = <String, double>{
        for (final q in quotesMap.entries)
          if (q.value.price != null && q.value.price!.isFinite)
            q.key: q.value.price!,
      };
      unawaited(_saveCurrentState(prefs, now, newPrices));

      return AwayChangesData(
        items: changes,
        lastVisit: lastVisit,
      );
    },
    onFailure: (f) => AwayChangesData.empty(
      lastVisit: lastVisitMs != null ? DateTime.fromMillisecondsSinceEpoch(lastVisitMs) : null,
      errorMessage: 'Değişim verisi alınamadı: $f',
    ),
  );
});

Future<void> _saveCurrentState(
  SharedPreferences? prefs,
  DateTime now,
  Map<String, double> prices,
) async {
  if (prefs == null) return;
  await prefs.setInt('away_last_visit_ms', now.millisecondsSinceEpoch);
  await prefs.setString('away_last_prices', _stringifyJson(prices));
}

String _stringifyJson(Map<String, double> map) {
  final buf = StringBuffer('{');
  var first = true;
  for (final entry in map.entries) {
    if (!first) buf.write(',');
    buf.write('"${entry.key}":${entry.value}');
    first = false;
  }
  buf.write('}');
  return buf.toString();
}

Map<String, dynamic> _parseJson(String json) {
  // Basit JSON parse - Map<String, double> için
  final trimmed = json.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return {};
  final content = trimmed.substring(1, trimmed.length - 1);
  if (content.isEmpty) return {};
  final result = <String, dynamic>{};
  for (final pair in content.split(',')) {
    final parts = pair.split(':');
    if (parts.length == 2) {
      final key = parts[0].trim().replaceAll('"', '');
      final value = double.tryParse(parts[1].trim());
      if (value != null) result[key] = value;
    }
  }
  return result;
}