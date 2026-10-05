import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart' show ScreenTitle;
import 'movement_radar_provider.dart';

/// Hareket Radarı kartı.
///
/// En çok hareket eden varlıkları listeler.
/// Sadece mevcut gerçek veriler kullanılır.
class MovementRadarCard extends ConsumerWidget {
  const MovementRadarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movementRadarProvider);

    return async.when(
      data: (data) {
        if (data.items.isEmpty) {
          if (data.errorMessage != null) {
            return _buildCard(context, 'Radar verisi yüklenemedi.', isError: true);
          }
          return _buildCard(
            context,
            'Şu an belirgin hareket eden varlık yok.',
            isInfo: true,
          );
        }

        return _buildCard(context, null, items: data.items);
      },
      loading: () => _buildCard(context, 'Radar taranıyor...', isLoading: true),
      error: (e, _) => _buildCard(context, 'Radar verisi yüklenemedi.', isError: true),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String? message, {
    List<RadarItem>? items,
    bool isInfo = false,
    bool isError = false,
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? AppPalette.lossSoft
            : isInfo
                ? AppPalette.gold.withValues(alpha: 0.1)
                : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? AppPalette.loss.withValues(alpha: 0.3)
              : theme.dividerTheme.color ?? Colors.grey,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.radar_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '🔥 Hareket Radarı',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (items != null && items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...items.map((item) => _RadarItemRow(item: item)),
          ],
          const SizedBox(height: 6),
          Text(
            'Sıralama: Günlük % değişimin mutlak büyüklüğüne göre.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarItemRow extends StatelessWidget {
  const _RadarItemRow({required this.item});

  final RadarItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = item.changePercent >= 0;
    final color = isPositive ? AppPalette.gain : AppPalette.loss;
    final sign = isPositive ? '+' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // İsim ve sembol
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  item.symbol,
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
          // Kategori
          SizedBox(
            width: 60,
            child: Text(
              item.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.neutral,
                fontSize: 10,
              ),
            ),
          ),
          // Fiyat
          SizedBox(
            width: 80,
            child: Text(
              TrFormat.price(item.price),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // % Değişim
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$sign${item.changePercent.toStringAsFixed(2)}%',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}