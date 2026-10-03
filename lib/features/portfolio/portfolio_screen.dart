import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/portfolio.dart';
import '../../domain/portfolio/portfolio_calculator.dart';
import '../../shared/widgets/common.dart';
import 'portfolio_providers.dart';
import 'transaction_sheet.dart';

/// Portfoy - varlik takibi ve kar/zarar (Aşama 11).
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(portfolioSummaryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('İşlem Ekle'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenTitle(
            title: 'Portföy',
            subtitle: 'Alım-satım işlemleriniz ve kar/zarar durumu',
          ),
          Expanded(
            child: _PortfolioBody(async: summary),
          ),
        ],
      ),
    );
  }
}

class _PortfolioBody extends ConsumerWidget {
  const _PortfolioBody({required this.async});

  final AsyncValue<PortfolioSummary> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(portfolioProvider);

    if (transactions.isEmpty) {
      return const EmptyStateView(
        message:
            'Portföyünüz boş.\nİlk işleminizi ekleyerek başlayın.',
        icon: Icons.account_balance_wallet_outlined,
        actionLabel: 'İşlem Ekle',
      );
    }

    final view = toViewState<PortfolioSummary>(
      async,
      isEmpty: (s) => s.isEmpty,
    );

    return StateView<PortfolioSummary>(
      state: view,
      onRetry: () => ref.invalidate(portfolioSummaryProvider),
      emptyMessage: 'Portföyünüz boş.',
      emptyIcon: Icons.account_balance_wallet_outlined,
      builder: (summary) => _SummaryView(summary: summary),
    );
  }
}

class _SummaryView extends ConsumerWidget {
  const _SummaryView({required this.summary});

  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plColor = AppPalette.direction(summary.profitLoss);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(portfolioSummaryProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          // ---- Toplam kart ----
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Toplam Değer',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${TrFormat.money(summary.totalValue)} TL',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        context,
                        'Toplam Maliyet',
                        '${TrFormat.money(summary.totalCost)} TL',
                        theme.colorScheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        context,
                        'Kâr / Zarar',
                        '${TrFormat.signed(summary.profitLoss)} TL',
                        plColor,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        context,
                        'Kâr/Zarar %',
                        TrFormat.percent(summary.profitLossPercent),
                        plColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.trending_up_rounded,
                        size: 16, color: AppPalette.direction(summary.dayChange)),
                    const SizedBox(width: 6),
                    Text(
                      'Günlük değişim: '
                      '${TrFormat.signed(summary.dayChange)} TL '
                      '(${TrFormat.percent(summary.dayChangePercent)})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.direction(summary.dayChange),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (summary.hasMissingPrices) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.neutral.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AppPalette.neutral),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bazı varlıkların güncel fiyatı alınamadı. '
                      'Bu kalemler toplam değere dahil edilmedi.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ---- Dagitim ----
          if (summary.items.isNotEmpty) ...[
            const SectionHeader(title: 'Varlık Dağılımı'),
            _AllocationCard(summary: summary),
          ],

          // ---- Kalemler ----
          const SectionHeader(title: 'Pozisyonlar'),
          for (final item in summary.items)
            _PositionTile(item: item, summary: summary),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.neutral,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.summary});

  final PortfolioSummary summary;

  static const List<Color> _palette = [
    Color(0xFFD4A017),
    Color(0xFF12A150),
    Color(0xFF3B82F6),
    Color(0xFFE53935),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = summary.totalValue;
    if (total <= 0) return const SizedBox.shrink();

    final rows = PortfolioCalculator.allocation(summary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        children: [
          // Yatay pay cubugu
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Expanded(
                      flex: (rows[i].share * 100).round().clamp(1, 1000),
                      child: Container(
                        color: _palette[i % _palette.length],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _palette[i % _palette.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${TrFormat.money(rows[i].value)} TL',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(
                      TrFormat.percent(rows[i].share, withSign: false),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PositionTile extends ConsumerWidget {
  const _PositionTile({required this.item, required this.summary});

  final PortfolioItem item;
  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plColor = AppPalette.direction(item.hasPrice ? item.profitLoss : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => openAssetDetail(context, item.assetId),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: theme.dividerTheme.color ?? Colors.grey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.assetName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.hasPrice
                              ? '${TrFormat.money(item.currentValue)} TL'
                              : TrFormat.noData,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (item.hasPrice)
                          Text(
                            '${TrFormat.signed(item.profitLoss)} TL '
                            '(${TrFormat.percent(item.profitLossPercent)})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: plColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _cell(
                      context,
                      'Miktar',
                      '${TrFormat.money(item.totalQuantity)} '
                          '${_unit(item.assetId)}',
                    ),
                    _cell(context, 'Ort. Maliyet',
                        '${TrFormat.money(item.avgCost)} TL'),
                    _cell(context, 'Güncel Fiyat',
                        item.hasPrice
                            ? '${TrFormat.money(item.currentPrice)} TL'
                            : TrFormat.noData),
                  ],
                ),
                if (!item.hasPrice)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 14, color: AppPalette.neutral),
                        const SizedBox(width: 6),
                        Text(
                          'Fiyat alınamadı — bu kalem toplam değere dahil değil.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.neutral,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _unit(String assetId) {
    final id = assetId;
    if (id.contains('gram') || id.contains('bilezik') || id.contains('gumus')) {
      return 'g';
    }
    if (id.contains('ons')) return 'oz';
    if (id.endsWith('-try')) return '';
    return 'adet';
  }

  Widget _cell(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
