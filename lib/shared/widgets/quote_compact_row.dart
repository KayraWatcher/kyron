import 'package:flutter/material.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../shared/widgets/price_flash.dart';
import '../../shared/widgets/quote_card.dart';

/// Profesyonel finans uygulaması standardında kompakt liste satırı.
///
/// Tek satırda: Varlık adı/sembol · fiyat · değişim % · mini sparkline (opsiyonel) · alış/satış (dövizde).
/// Yükseklik ~56px; padding/minimum boşluk; dark/light tema uyumlu; taşma yok.
/// Dokunma → detay ekranı.
class QuoteCompactRow extends StatelessWidget {
  const QuoteCompactRow({
    super.key,
    required this.assetId,
    required this.quote,
    this.sparkline,
    this.onTap,
    this.showSpread = false,
  });

  final String assetId;
  final Quote quote;
  final SparklineData? sparkline;
  final VoidCallback? onTap;
  final bool showSpread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          // Alış/satım (döviz) ana satirin DISINDA: Row disi cocuklar
        // sinirsiz ana eksen kisiti alir; icerik Container sinirina kadar
        // sigmali. Column altinda kart genisligiyle sinirlidir.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // SOL: Mini sparkline / hareket grafiği
                if (sparkline?.isValid == true) ...[
                  Sparkline(
                    data: sparkline,
                    color: directionColor,
                    width: 48,
                    height: 22,
                  ),
                  const SizedBox(width: 12),
                ],
                // ORTA: Varlık adı + sembol
                Expanded(
                  child: _AssetIdentityCompact(
                    assetId: assetId,
                    quote: quote,
                  ),
                ),
                // SAĞ: fiyat + günlük değişim (saga hizali)
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: PriceFlash(
                        text: _priceText(asset, quote),
                        price: quote.price,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    ChangeBadge(
                      value: changePercent,
                      percent: true,
                      compact: true,
                      showArrow: false,
                    ),
                  ],
                ),
              ],
            ),

            // Alış/Satış (dövizde, showSpread true ise) - ikinci satır
            if (showSpread && (quote.bid != null || quote.ask != null)) ...[
              const SizedBox(height: 4),
              _BidAskCompact(quote: quote),
            ],
          ],
        ),
        ),
      ),
    );
  }

  String _priceText(AssetDescriptor? asset, Quote q) {
    final p = q.price;
    if (p == null || !p.isFinite) return TrFormat.noData;
    final currency = q.currency ?? asset?.currency ?? '';
    return '${TrFormat.price(p)} $currency';
  }
}

/// Kompakt varlık kimlik satırı: isim + sembol + tazelik rozeti.
class _AssetIdentityCompact extends StatelessWidget {
  const _AssetIdentityCompact({
    required this.assetId,
    required this.quote,
  });

  final String assetId;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final isStale = quote.isStale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          asset?.name ?? assetId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            if (asset != null) ...[
              Flexible(
                child: Text(
                  asset.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              if (asset.isCalculated) ...[
                const SizedBox(width: 4),
                Flexible(child: _CalculatedBadgeCompact(label: asset.category.label)),
              ] else ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    quote.source.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isStale ? AppPalette.loss : AppPalette.neutral,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
            if (isStale) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Bayat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.loss,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CalculatedBadgeCompact extends StatelessWidget {
  const _CalculatedBadgeCompact({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppPalette.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppPalette.goldDeep,
        ),
      ),
    );
  }
}

/// Döviz için alış/satış kompakt satırı.
class _BidAskCompact extends StatelessWidget {
  const _BidAskCompact({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell(context, 'Al', quote.bid),
        const SizedBox(width: 6),
        _cell(context, 'Sat', quote.ask),
        if (quote.spread != null) ...[
          const SizedBox(width: 6),
          _cell(context, 'Mk', quote.spread, decimals: 4),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, String label, double? value,
      {int decimals = 2}) {
    final theme = Theme.of(context);
    final text =
        value == null ? TrFormat.noData : TrFormat.money(value, decimals: decimals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.neutral,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            text,
            maxLines: 1,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}