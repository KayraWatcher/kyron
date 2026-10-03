import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/cache_policy.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/candle.dart';
import '../../shared/widgets/quote_card.dart';

/// Varlik kartlari icin mini grafik serisi.
///
/// Gunluk mum serisinden uretilir; yaklasik 60 mum kullanilir ki
/// cagri sayisi ve bellek tuketimi dusuk kalsin. 60 saniyede bir yenilenir,
/// 5 dakika kullanilmazsa bellekten dusurulur.
final miniChartProvider = FutureProvider.autoDispose
    .family<SparklineData?, String>((ref, assetId) async {
  Future<SparklineData?> fetch() async {
    final repo = ref.read(marketRepositoryProvider);
    final res = await repo.getCandles(
      assetId: assetId,
      interval: ChartInterval.d1,
      limit: 60,
    );
    final series = res.dataOrNull;
    if (series == null) return null;
    return SparklineData.fromCandles(series.candles);
  }

  final keepAlive = ref.keepAlive();
  final expiry = Timer(CachePolicy.miniChartKeepAlive, keepAlive.close);

  // Periyodik yenileme: provider'i kendi kendine tazeler; boylece asla
  // bayat/grafik-disi bir deger gosterilmez. Aralik fiyat TTL'i ile uyumludur.
  // Arka planda istek atilmaz - cizim gorunurken gerekli, arkada gereksiz.
  final timer = Timer.periodic(CachePolicy.miniChartRefreshInterval, (_) {
    if (!ref.mounted) return;
    if (!ref.read(appInForegroundProvider)) return;
    ref.invalidateSelf();
  });

  ref.onDispose(() {
    timer.cancel();
    expiry.cancel();
  });

  return fetch();
});
