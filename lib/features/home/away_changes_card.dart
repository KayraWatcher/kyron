import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart'
    show TrFormat; // TrFormat.price, TrFormat.relativeTime
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart' show ScreenTitle;
import 'away_changes_provider.dart';
import 'away_selection_sheet.dart';

/// "Sen Yokken Ne Oldu?" kartı.
///
/// Son uygulama ziyaretinden bu yana **kullanıcının seçtiği** varlıkların
/// değişimlerini gösterir (sıra dahil). Varsayılan: Gram Altın + Çeyrek Altın.
/// Bölüm yalnızca hangi asset'lerin gösterileceğini seçer; değişim hesabı
/// ve veri kaynakları aynıdır. İlk açılışta veri yoksa gizlenir.
/// Kartın altında seçimi değiştiren kalıcı bir "Düzenle" kontrolü bulunur.
class AwayChangesCard extends ConsumerWidget {
  const AwayChangesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(awayChangesProvider);
    final selection = ref.watch(awaySelectionProvider);

    return async.when(
      data: (data) {
        if (!data.hasData) {
          if (data.errorMessage != null) {
            return _buildCard(
              context,
              ref,
              message: 'Değişim verisi yüklenemedi.',
              isError: true,
            );
          }
          // İlk açılışta veri yoksa kartı gizle (boş alan bırakma)
          return const SizedBox.shrink();
        }

        // Seçime göre filtrele + kullanıcı sırasını uygula.
        final items = applyAwaySelection(
          items: data.items,
          selection: selection,
        );

        return _buildCard(
          context,
          ref,
          items: items,
          lastVisit: data.lastVisit,
          isEmpty:
              items.isEmpty, // veri var ama seçili varlıklar değişmemiş
        );
      },
      loading: () => const SizedBox.shrink(), // Yükleme sırasında gizle
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref, {
    String? message,
    List<AwayChangeItem>? items,
    DateTime? lastVisit,
    bool isError = false,
    bool isEmpty = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? AppPalette.lossSoft
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
                Icons.history_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'SEN YOKKEN NE OLDU?',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (lastVisit != null) ...[
                const SizedBox(width: 8),
                Text(
                  // relativeTime zaten "7 dk önce" / "Az önce" bicimi dondurur;
                  // burada tekrar "once" eklemek "(... once once)" yapiyordu.
                  '(${TrFormat.relativeTime(lastVisit)})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.neutral,
                    fontSize: 11,
                  ),
                ),
              ],
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
            ...items.map((item) => _AwayItemRow(item: item)),
          ],
          // Seçili varlıkların hiçbiri belirgin değişmemiş: bölümü boş
          // bırakma, seçimi düzenleyebilmek için kısa bir not + kontrol.
          if (isEmpty && message == null) ...[
            const SizedBox(height: 10),
            Text(
              'Seçili varlıklarda belirgin bir değişim yok.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.neutral,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => showAwaySelectionSheet(context, ref),
                child: const Text('Düzenle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AwayItemRow extends StatelessWidget {
  const _AwayItemRow({required this.item});

  final AwayChangeItem item;

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
          // Önceki fiyat
          SizedBox(
            width: 70,
            child: Text(
              TrFormat.price(item.previousPrice),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.neutral,
                fontSize: 11,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 14,
            color: AppPalette.neutral,
          ),
          const SizedBox(width: 6),
          // Güncel fiyat
          SizedBox(
            width: 70,
            child: Text(
              TrFormat.price(item.currentPrice),
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