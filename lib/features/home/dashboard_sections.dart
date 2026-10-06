import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../shared/shell/app_shell.dart';
import '../../shared/widgets/common.dart' show SectionHeader;
import '../../shared/widgets/quote_card.dart' show ChangeBadge;
import '../markets/markets_providers.dart';
import '../markets/movement_radar_provider.dart';
import 'home_providers.dart';
import 'market_status_provider.dart';

// ---------------------------------------------------------------------------
// 1) Canlı bağlantı durumu + piyasa özeti şeridi
// ---------------------------------------------------------------------------

/// Canlı veri bağlantısının kullanıcıya anlaşılır özeti.
///
/// **Dürüstlük kuralı:** "Canlı veriler" yazısı yalnızca ekranda **gerçekten**
/// canlı (taze akış) fiyat varsa görünür. Bağlantı yoksa ya da veri
/// yükleniyorsa durum açıkça yazılır; hiçbir zaman sahte "canlı" gösterilmez.
class LiveConnectionBar extends StatelessWidget {
  const LiveConnectionBar({
    super.key,
    required this.quotes,
    required this.loading,
    required this.offline,
  });

  final Map<String, Quote>? quotes;
  final bool loading;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, icon, color) = _state();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Consumer(
                  builder: (context, ref, _) {
                    final status = ref.watch(marketStatusProvider).value;
                    if (status == null) return const SizedBox.shrink();
                    return Text(
                      'Borsa: ${status.bistStatus.label} · '
                      'Döviz: ${status.forexStatus.label} · '
                      'Metaller: ${status.metalsStatus.label}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.neutral,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color) _state() {
    final map = quotes;
    if (offline) {
      return (
        'Çevrimdışısınız — son bilinen veriler gösteriliyor',
        Icons.wifi_off_rounded,
        AppPalette.loss,
      );
    }
    if (loading || map == null || map.isEmpty) {
      return (
        'Veri bağlantısı kuruluyor…',
        Icons.sync_rounded,
        AppPalette.neutral,
      );
    }
    if (map.values.every((q) => q.isStale)) {
      return (
        'Veri bağlantısı yenileniyor — son bilinen veriler',
        Icons.sync_problem_rounded,
        AppPalette.loss,
      );
    }
    final live = map.values.any((q) => q.freshness == DataFreshness.live);
    if (live) {
      return ('Canlı veriler — bağlantı aktif', Icons.bolt_rounded, AppPalette.gain);
    }
    return (
      'Bağlantı kuruldu — piyasa kapalı, son kapanış gösteriliyor',
      Icons.schedule_rounded,
      AppPalette.goldDeep,
    );
  }
}

// ---------------------------------------------------------------------------
// 2) Günün en çok hareket edenleri
// ---------------------------------------------------------------------------

/// Günün en çok hareket eden varlıkları (yalnız gerçek değişim verisi).
///
/// Hareket radarı sağlayıcısını **yeniden kullanır**; burada yeni bir hesap
/// veya sahte liste üretilmez.
class TopMoversSection extends ConsumerWidget {
  const TopMoversSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radar = ref.watch(movementRadarProvider).value;
    final items = radar?.items ?? const <RadarItem>[];

    // Veri yoksa bölüm **hiç gösterilmez** (boş kutu yasak).
    if (items.isEmpty) return const SizedBox.shrink();

    final top = items.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Günün En Çok Hareket Edenleri',
          action: 'Tümü',
          onAction: () => selectSection(ref, AppSection.markets),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _MoverCard(item: top[i]),
          ),
        ),
      ],
    );
  }
}

class _MoverCard extends StatelessWidget {
  const _MoverCard({required this.item});

  final RadarItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppPalette.direction(item.changePercent);

    return SizedBox(
      width: 168,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => openAssetDetail(context, item.assetId),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ChangeBadge(
                  value: item.changePercent,
                  percent: true,
                  compact: true,
                ),
                const Spacer(),
                Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.neutral,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3) Kategori navigasyonu
// ---------------------------------------------------------------------------

/// Kategori kartlari: her kategori varlik sayisi ve en cok hareket eden
/// varligiyla gorunur; dokununca Piyasalar ekraninda o kategori acilir.
///
/// Katalogda **varligi olmayan** kategoriler hic gosterilmez (bos kart /
/// sahte sayi uretilmez).
class CategoryNavSection extends ConsumerWidget {
  const CategoryNavSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(homeQuotesProvider).value;
    final radar = ref.watch(movementRadarProvider).value;

    // Kategori -> indeksi `AssetCategory.values` sirasiyla birebir ortusur
    // (Piyasalar ekrani da ayni sirayi kullanir).
    final entries = <(AssetCategory, int, List<AssetDescriptor>, RadarItem?)>[];
    for (var i = 0; i < AssetCategory.values.length; i++) {
      final cat = AssetCategory.values[i];
      final assets = AssetCatalog.byCategory(cat);
      if (assets.isEmpty) continue;
      final ids = assets.map((a) => a.id).toSet();
      final mover = (radar?.items ?? const <RadarItem>[])
          .where((r) => ids.contains(r.assetId))
          .firstOrNull;
      entries.add((cat, i, assets, mover));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Kategoriler',
          action: 'Tümü',
          onAction: () => selectSection(ref, AppSection.markets),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (cat, index, assets, mover) in entries)
                _CategoryChip(
                  category: cat,
                  count: assets.length,
                  mover: mover,
                  onTap: () {
                    ref.read(marketCategoryProvider.notifier).select(index);
                    selectSection(ref, AppSection.markets);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.count,
    required this.mover,
    required this.onTap,
  });

  final AssetCategory category;
  final int count;
  final RadarItem? mover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = mover?.changePercent;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.neutral,
                ),
              ),
              if (change != null) ...[
                const SizedBox(width: 8),
                ChangeBadge(
                  value: change,
                  percent: true,
                  showArrow: false,
                  compact: true,
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
