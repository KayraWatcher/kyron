import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/watchlist_provider.dart';
import '../../core/theme/app_theme.dart';

/// Takip listesi yildizi (favori).
///
/// Kullanici bir varligi yildizlayarak ana sayfadaki "Takip Edilenler"
/// bolumune ekler; tercih [watchlistProvider] uzerinden **kalıcı** olarak
/// saklanir. Tum ekranlar ayni provider'i izledigi icin bir yerde yapilan
/// degisiklik diger ekranlarda aninda gorunur.
class WatchStar extends ConsumerWidget {
  const WatchStar({
    super.key,
    required this.assetId,
    this.size = 22,
    this.tooltipPrefix = '',
  });

  final String assetId;

  /// Simge boyutu (kart icin kucuk, detay basligi icin buyuk).
  final double size;

  /// Kategori gibi one eklenen ipucu oneki (opsiyonel).
  final String tooltipPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(watchlistProvider);
    final active = watch.contains(assetId);

    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 10, minHeight: size + 10),
      tooltip: active
          ? '${tooltipPrefix}Takip listesinden çıkar'
          : '${tooltipPrefix}Takip listesine ekle',
      icon: Icon(
        active ? Icons.star_rounded : Icons.star_border_rounded,
        size: size,
        color: active ? AppPalette.gold : AppPalette.neutral,
      ),
      onPressed: () => ref.read(watchlistProvider.notifier).toggle(assetId),
    );
  }
}
