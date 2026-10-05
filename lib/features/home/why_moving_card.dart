import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart' show ScreenTitle;
import 'why_moving_providers.dart';

/// "Neden Hareket Ediyor?" kartı.
///
/// Bir varlığın günlük değişiminin muhtemel nedenlerini gösterir.
/// Sadece mevcut gerçek veriler kullanılır; uydurma/yorum yapmaz.
class WhyMovingCard extends ConsumerWidget {
  const WhyMovingCard({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(whyMovingProvider(assetId));

    return async.when(
      data: (data) {
        if (data.insufficientData) {
          return _buildCard(
            context,
            message: 'Bu hareket için yeterli doğrulanabilir veri bulunamadı.',
            isInfo: true,
          );
        }
        if (data.errorMessage != null) {
          return _buildCard(
            context,
            message: 'Neden analizi yüklenemedi.',
            isError: true,
          );
        }

        final parts = <Widget>[];
        if (data.primaryReason != null) {
          parts.add(_ReasonLine(
            label: 'Ana etken',
            value: data.primaryReason!,
            isPrimary: true,
          ));
        }
        if (data.secondaryReason != null) {
          parts.add(_ReasonLine(
            label: 'İkincil etken',
            value: data.secondaryReason!,
            isPrimary: false,
          ));
        }

        if (parts.isEmpty) {
          return _buildCard(
            context,
            message: 'Bu hareket için yeterli doğrulanabilir veri bulunamadı.',
            isInfo: true,
          );
        }

        return _buildCard(
          context,
          children: parts,
        );
      },
      loading: () => _buildCard(
        context,
        message: 'Analiz hazırlanıyor...',
        isLoading: true,
      ),
      error: (e, _) => _buildCard(
        context,
        message: 'Neden analizi yüklenemedi.',
        isError: true,
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    String? message,
    List<Widget>? children,
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
                isError
                    ? Icons.error_outline_rounded
                    : isInfo
                        ? Icons.info_outline_rounded
                        : isLoading
                            ? Icons.hourglass_empty_rounded
                            : Icons.analytics_outlined,
                size: 18,
                color: isError
                    ? AppPalette.loss
                    : isInfo
                        ? AppPalette.goldDeep
                        : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Neden Hareket Ediyor?',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isError
                      ? AppPalette.loss
                      : isInfo
                          ? AppPalette.goldDeep
                          : theme.colorScheme.primary,
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
          if (children != null) ...[
            const SizedBox(height: 8),
            ...children,
          ],
          const SizedBox(height: 6),
          Text(
            'Bu analiz mevcut piyasa verilerine dayanır; yatırım tavsiyesi değildir.',
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

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({
    required this.label,
    required this.value,
    required this.isPrimary,
  });

  final String label;
  final String value;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Değerden renk çıkar (varsa + / - prefix)
    final isPositive = value.contains('+');
    final isNegative = value.contains('-') && !value.startsWith('-');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.neutral,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isPrimary
                    ? (isPositive
                        ? AppPalette.gain
                        : isNegative
                            ? AppPalette.loss
                            : theme.colorScheme.onSurface)
                    : theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (isPrimary) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ANA',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  color: AppPalette.goldDeep,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}