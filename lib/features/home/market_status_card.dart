import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'market_status_provider.dart' show MarketStatusData, computeMarketStatus, MarketStatus, marketStatusProvider;

/// Piyasa durumu gostergesi karti.
///
/// Gercek sistem saati ile BIST/Forex/Metaller durumunu gosterir.
/// Fake timer kullanmaz.
class MarketStatusCard extends ConsumerWidget {
  const MarketStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(marketStatusProvider);

    return async.when(
      data: (data) => _buildCard(context, data),
      loading: () => _buildCard(context, computeMarketStatus()),
      error: (_, __) => _buildCard(context, computeMarketStatus()),
    );
  }

  Widget _buildCard(BuildContext context, MarketStatusData data) {
    final theme = Theme.of(context);
    final isAnyOpen = data.anyOpen;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAnyOpen
              ? AppPalette.gain.withValues(alpha: 0.3)
              : AppPalette.loss.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isAnyOpen ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 16,
                color: isAnyOpen ? AppPalette.gain : AppPalette.loss,
              ),
              const SizedBox(width: 8),
              Text(
                'PİYASA DURUMU',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (data.lastUpdated != null)
                Text(
                  'Güncellendi: ${_formatTime(data.lastUpdated!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.neutral,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Borsa İstanbul',
            status: data.bistStatus,
          ),
          const SizedBox(height: 4),
          _StatusRow(
            label: 'Döviz / Forex',
            status: data.forexStatus,
          ),
          const SizedBox(height: 4),
          _StatusRow(
            label: 'Metaller / Ons',
            status: data.metalsStatus,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.status});

  final String label;
  final MarketStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = status == MarketStatus.open;
    final color = isOpen ? AppPalette.gain : AppPalette.loss;
    final icon = isOpen ? Icons.check_circle_rounded : Icons.cancel_rounded;

    String statusText;
    switch (status) {
      case MarketStatus.open:
        statusText = 'Açık';
        break;
      case MarketStatus.closed:
        statusText = 'Kapalı';
        break;
      case MarketStatus.preMarket:
        statusText = 'Ön Seans';
        break;
      case MarketStatus.postMarket:
        statusText = 'Kapanış Sonrası';
        break;
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusText,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}