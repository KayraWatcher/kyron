import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../domain/repositories/market_data_repository.dart';

/// Hareket Radarı öğesi.
class RadarItem {
  const RadarItem({
    required this.assetId,
    required this.name,
    required this.symbol,
    required this.changePercent,
    required this.price,
    required this.category,
  });

  final String assetId;
  final String name;
  final String symbol;
  final double changePercent;
  final double price;
  final String category;
}

/// Hareket Radarı verisi.
class MovementRadarData {
  const MovementRadarData({
    required this.items,
    this.errorMessage,
  });

  final List<RadarItem> items;
  final String? errorMessage;

  factory MovementRadarData.empty({String? errorMessage}) =>
      MovementRadarData(items: [], errorMessage: errorMessage);
}

/// En çok hareket eden varlıkları (pozitif/negatif) getiren provider.
///
/// Mevcut piyasa verilerine dayanır; fake veri üretmez.
final movementRadarProvider = FutureProvider.autoDispose<MovementRadarData>((
  ref,
) async {
  final repo = ref.watch(marketRepositoryProvider);

  // Tüm katalog ID'leri için quote getir
  final allIds = AssetCatalog.all.map((a) => a.id).toList();
  final quotesResult = await repo.getQuotes(allIds);

  return quotesResult.when(
    onSuccess: (quotesMap) {
      final radarItems = <RadarItem>[];

      for (final asset in AssetCatalog.all) {
        final quote = quotesMap[asset.id];
        if (quote == null || quote.effectiveChangePercent == null) continue;

        final change = quote.effectiveChangePercent!;
        // Sadece anlamlı hareketleri al (mutlak > 0.1%)
        if (change.abs() < 0.1) continue;

        radarItems.add(RadarItem(
          assetId: asset.id,
          name: asset.name,
          symbol: asset.symbol,
          changePercent: change,
          price: quote.price ?? 0,
          category: asset.category.label,
        ));
      }

      // Mutlak değişim büyüklüğüne göre sırala (en çok hareket eden üstte)
      radarItems.sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));

      // En fazla 10 öğe göster
      final topItems = radarItems.take(10).toList();

      return MovementRadarData(items: topItems);
    },
    onFailure: (f) => MovementRadarData.empty(
      errorMessage: 'Radar verisi alınamadı: $f',
    ),
  );
});