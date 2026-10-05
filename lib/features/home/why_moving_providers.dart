import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/state_failure.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../domain/repositories/market_data_repository.dart';

/// "Neden Hareket Ediyor?" verisi.
///
/// Bir varlığın günlük değişimini (Ons Altın, USD/TRY vb. bileşenlerine)
/// böler ve en etkili bileşeni gösterir.
/// SADECE mevcut sağlayıcı verilerini kullanır; uydurma yapmaz.
class WhyMovingData {
  const WhyMovingData({
    required this.assetId,
    this.primaryReason,
    this.secondaryReason,
    this.insufficientData = false,
    this.errorMessage,
  });

  final String assetId;
  final String? primaryReason;   // Örn: "Ons Altın +1.2%"
  final String? secondaryReason; // Örn: "USD/TRY +0.3%"
  final bool insufficientData;
  final String? errorMessage;

  factory WhyMovingData.empty(String assetId) =>
      WhyMovingData(assetId: assetId, insufficientData: true);

  factory WhyMovingData.error(String assetId, String message) =>
      WhyMovingData(assetId: assetId, errorMessage: message);
}

/// Her varlık için "Neden Hareket Ediyor?" hesaplayıcı.
final whyMovingProvider = FutureProvider.autoDispose
    .family<WhyMovingData, String>((ref, assetId) async {
  final repo = ref.watch(marketRepositoryProvider);

  // Ana varlık ve bileşenleri getir
  final asset = AssetCatalog.byId(assetId);
  if (asset == null || asset.parentIds.isEmpty) {
    return WhyMovingData.empty(assetId);
  }

  // Ana varlık ve tüm parent ID'leri için quote getir
  final ids = [assetId, ...asset.parentIds];
  final quotesResult = await repo.getQuotes(ids);

  return quotesResult.when(
    onSuccess: (quotesMap) {
      final mainQuote = quotesMap[assetId];
      if (mainQuote == null || mainQuote.effectiveChangePercent == null) {
        return WhyMovingData.empty(assetId);
      }

      final mainChange = mainQuote.effectiveChangePercent!;

      // Parent'ların değişimlerini topla
      final reasons = <String>[];
      for (final parentId in asset.parentIds) {
        final parentQuote = quotesMap[parentId];
        if (parentQuote?.effectiveChangePercent != null) {
          final parentAsset = AssetCatalog.byId(parentId);
          final name = parentAsset?.name ?? parentId;
          final pct = parentQuote!.effectiveChangePercent!;
          if (pct != 0) {
            final sign = pct > 0 ? '+' : '';
            reasons.add('$name $sign${pct.toStringAsFixed(2)}%');
          }
        }
      }

      if (reasons.isEmpty) {
        return WhyMovingData.empty(assetId);
      }

      // En yüksek mutlak etkili olanı primary yap
      reasons.sort((a, b) {
        final aVal = double.tryParse(a.split(' ').last.replaceAll('%', '')) ?? 0;
        final bVal = double.tryParse(b.split(' ').last.replaceAll('%', '')) ?? 0;
        return bVal.abs().compareTo(aVal.abs());
      });

      return WhyMovingData(
        assetId: assetId,
        primaryReason: reasons.first,
        secondaryReason: reasons.length > 1 ? reasons[1] : null,
      );
    },
    onFailure: (f) => WhyMovingData.error(assetId, 'Veri alınamadı: $f'),
  );
});