import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';

/// Kart ustu mini grafik icin cizim verisi.
///
/// Gercek mum serisinden turetilir; hicbir yerde sahte/uretilmis
/// seri kullanilmaz. Veri yoksa cizim yapilmaz.
class SparklineData {
  const SparklineData(this.values);

  final List<double> values;

  bool get isValid => values.length >= 2;

  static SparklineData? fromCandles(List<Candle> candles) {
    if (candles.length < 2) return null;
    final values = <double>[];
    for (final c in candles) {
      if (c.close.isFinite) values.add(c.close);
    }
    if (values.length < 2) return null;
    return SparklineData(values);
  }

  static SparklineData? fromQuotes(List<Quote> quotes) {
    if (quotes.length < 2) return null;
    final values = <double>[];
    for (final q in quotes) {
      final p = q.price;
      if (p != null && p.isFinite) values.add(p);
    }
    if (values.length < 2) return null;
    return SparklineData(values);
  }
}

/// Mini cizgi grafik - kartin sag ust kosesinde.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.data,
    required this.color,
    this.width = 72,
    this.height = 32,
  });

  final SparklineData? data;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || !d.isValid) {
      // Veri yoksa bos alan goster; sahte cizgi cizilmez.
      return SizedBox(width: width, height: height);
    }
    return SizedBox(
      width: width,
      height: height,
      // Mini grafik kendi cizim katmaninda yalitilir; fiyat karti
      // yeniden cizilirken sparkline'in tekrar boyanmasi onlenir.
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SparklinePainter(values: d.values, color: color),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;

    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = max - min;
    if (range <= 0) {
      // Tum degerler ayni -> yatay cizgi.
      final y = size.height / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - ((values[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Alt kisim dolgusu.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      !listEquals(old.values, values) || old.color != color;
}

/// Varlik adi + kategori rozeti.
class AssetIdentity extends StatelessWidget {
  const AssetIdentity({
    super.key,
    required this.assetId,
    this.subtitle,
    this.freshness,
    this.isStale = false,
  });

  final String assetId;
  final String? subtitle;

  /// Veri tazeligi rozeti (opsiyonel).
  ///
  /// "Canlı" yazisi yalnizca [DataFreshness.live] durumunda gorunur.
  final DataFreshness? freshness;

  /// Son istek basarisiz oldu; goruntulenen deger **guncel degil**.
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          asset?.name ?? assetId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (asset != null) ...[
              // Varligin sembolu: dar kartta **esne**kir olmali. Sabit
              // genislikte birakilirsa (orn. "CUMHURIYET" + kategori rozeti)
              // satir kart sinirini asabilir ve RendererFlex tasma hatasi
              // uretir; Flexible + ellipsis ile genislik asiminda metin
              // kirpilir, hata uretilmez.
              Flexible(
                child: Text(
                  asset.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
              if (asset.isCalculated) ...[
                const SizedBox(width: 6),
                Flexible(child: _CalculatedBadge(label: asset.category.label)),
              ] else if (subtitle != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.neutral,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
              if (freshness != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Tooltip(
                    message: isStale
                        ? 'Son istek başarısız; gösterilen değer güncel '
                            'değil. Uygulama kendiliğinden yeniden deniyor.'
                        : freshness!.description,
                    child: Text(
                      isStale ? 'Bağlantı yok' : freshness!.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isStale ? AppPalette.loss : AppPalette.neutral,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

/// "Hesaplanan" etiketi - dogrudan piyasa verisinden ayirmak icin.
class _CalculatedBadge extends StatelessWidget {
  const _CalculatedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppPalette.goldDeep,
        ),
      ),
    );
  }
}

/// Yuzde/deger degisim rozeti (yesil/kirmizi/nötr).
class ChangeBadge extends StatelessWidget {
  const ChangeBadge({
    super.key,
    required this.value,
    this.percent = false,
    this.showArrow = true,
    this.compact = false,
  });

  /// Gosterilecek deger; null ise "—" yazilir.
  final double? value;

  /// true: "%+1,42", false: "+0,45"
  final bool percent;
  final bool showArrow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = value != null && value!.isFinite;
    final color = AppPalette.direction(valid ? value : null);
    final text = percent
        ? TrFormat.percent(value)
        : TrFormat.signed(value, decimals: 2);

    if (!valid) {
      return Text(
        TrFormat.noData,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppPalette.neutral,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showArrow) ...[
          Icon(
            value! >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: compact ? 12 : 14,
            color: color,
          ),
          const SizedBox(width: 2),
        ],
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 12 : 13,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Ana sayfa/kartlar icin tek varlik fiyat karti.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.assetId,
    required this.quote,
    this.sparkline,
    this.onTap,
    this.trailing,
    this.showSpread = false,
  });

  final String assetId;
  final Quote quote;
  final SparklineData? sparkline;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showSpread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Dar grid hucrelerinde (genislik < 160) kompakt mod:
            // azaltik padding, esnek sparkline, kompakt bid/ask.
            // Yukseklik icin threshold 175: altinda padding/spacing azaltilir.
            final isNarrow = constraints.maxWidth < 160;
            final isShort = constraints.maxHeight < 175;
            final hPadding = isNarrow ? 10.0 : 14.0;
            final vPadding = isShort ? 6.0 : (isNarrow ? 8.0 : 14.0);
            final spacing = isShort ? 4.0 : (isNarrow ? 6.0 : 10.0);
            final sparklineWidth = isNarrow ? 40.0 : 60.0;
            final sparklineHeight = isNarrow ? 22.0 : 30.0;
            final priceFontSize = isNarrow ? 18.0 : 22.0;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AssetIdentity(
                          assetId: assetId,
                          subtitle: quote.source.label,
                          freshness: quote.freshness,
                          isStale: quote.isStale,
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  SizedBox(height: spacing),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _priceText(asset, quote),
                                maxLines: 1,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: priceFontSize,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: (isNarrow || isShort) ? 2 : 4),
                            ChangeBadge(
                              value: changePercent,
                              percent: true,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                      Sparkline(
                        data: sparkline,
                        color: directionColor,
                        width: sparklineWidth,
                        height: sparklineHeight,
                      ),
                    ],
                  ),
                  if (showSpread && (quote.bid != null || quote.ask != null)) ...[
                    SizedBox(height: spacing),
                    isNarrow
                        ? _BidAskRowCompact(quote: quote)
                        : _BidAskRow(quote: quote),
                  ],
                ],
              ),
            );
          },
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

/// Kompakt alis/satis satiri - dar grid hucreleri icin.
class _BidAskRowCompact extends StatelessWidget {
  const _BidAskRowCompact({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _compactCell(context, 'Al', quote.bid),
        const SizedBox(width: 4),
        _compactCell(context, 'Sat', quote.ask),
        if (quote.spread != null) ...[
          const SizedBox(width: 4),
          _compactCell(context, 'Mk', quote.spread, decimals: 4),
        ],
      ],
    );
  }

  Widget _compactCell(BuildContext context, String label, double? value,
      {int decimals = 2}) {
    final theme = Theme.of(context);
    final text =
        value == null ? TrFormat.noData : TrFormat.money(value, decimals: decimals);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BidAskRow extends StatelessWidget {
  const _BidAskRow({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _cell(context, 'Alış', quote.bid),
        const SizedBox(width: 8),
        _cell(context, 'Satış', quote.ask),
        const SizedBox(width: 8),
        if (quote.spread != null)
          _cell(context, 'Makas', quote.spread, decimals: 4),
      ],
    );
  }

  Widget _cell(BuildContext context, String label, double? value,
      {int decimals = 2}) {
    final theme = Theme.of(context);
    final text =
        value == null ? TrFormat.noData : TrFormat.money(value, decimals: decimals);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          // Dar kartta deger iki satira bolunmesin; kirpmak yerine
          // olcusu kucultulur, boylece "0,0883" aynen gorunur.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
