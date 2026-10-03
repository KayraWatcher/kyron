import 'package:flutter/material.dart';

import '../../../core/format/tr_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/candle.dart';
import '../../charts/interactive_chart.dart';

/// Grafigin ustunde OHLC + hacim + tarih satiri.
///
/// Gereksinim (GOLD v2 / Faz E): ustbilgi **capraz imlecin uzerindeki
/// mumu** gosterir.
///
///  * Capraz imlec kapaliyken -> serideki **son** mum gosterilir.
///  * Capraz imlec acikken    -> imlecin isaret ettigi mumun A/Y/D/K,
///    hacmi ve tarihi gosterilir.
///  * Degerler yalnizca mumdan gelir. Mum yoksa satir **gizlenir**;
///    hicbir deger uydurulmaz / `null` gosterilmez.
class CandleOhlcBar extends StatelessWidget {
  const CandleOhlcBar({
    super.key,
    required this.candles,
    required this.interaction,
    this.decimals = 2,
  });

  final List<Candle> candles;

  /// Grafikten gelen etkilesim durumu (imlec konumu ve gorunurlugu).
  final ChartInteraction interaction;

  final int decimals;

  /// Secili mum indeksi (imlec yoksa son mum).
  int get _index {
    final ci = interaction.showCrosshair ? interaction.crosshairIndex : null;
    if (ci == null) return candles.length - 1;
    if (ci < 0) return 0;
    final last = candles.length - 1;
    return ci > last ? last : ci;
  }

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final c = candles[_index];
    final crosshairOn = interaction.showCrosshair && interaction.crosshairIndex != null;

    final when = DateTime.fromMillisecondsSinceEpoch(c.time);
    final rising = c.close >= c.open;
    final color = rising ? AppPalette.gain : AppPalette.loss;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      // NOT: Burada yatay kaydirma **yok**.
      //
      // Onceki surumde `SingleChildScrollView(scrollDirection: horizontal)`
      // vardi. Dar ekranda satir sigmayinca D/K/Hacim tamamen ekran disinda
      // kalyordu; ustelik Flutter'da klasen disindaki cocuklarin semantigi de
      // kesiligi icin ziyaret edilmez -> ekranda **gosterilmeyen degerler
      // gozlemlenemez** hale geliyordu (okunabilirlik + test edilebilirlik
      // kaybi). `Wrap` her degeri gorunur birakacak sekilde dogal olarak
      // kirpar; hicbir deger gizlenmez, kaydirma gerekmez.
      // KARARLILIK (cihaz kok nedeni, 2026-10-03): tarih aciklamasi ile
      // A/Y/D/K hucreleri **tek Wrap'te** oldugu icin tarihin uzunlugu
      // (canli modda "Son mum · " oneki) hucrelerin kirilma noktasini
      // degistiriyordu; imlec acilinca satir sayisi azalir, OHLC barinin
      // yuksekligi dar ekranda ~31px kisalir ve grafik alani kayardi.
      // Artik tarih kendi satirinda (tek satir + ellipsis) durur; hucreler
      // ayri Wrap'te akar. Iki modda da satir sayisi aynidir -> yukseklik
      // mod gecislerinde DEGMEZ.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                crosshairOn
                    ? Icons.my_location_rounded
                    : Icons.schedule_rounded,
                size: 13,
                color: AppPalette.neutral,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  crosshairOn
                      ? TrFormat.dateTime(when)
                      : 'Son mum · ${TrFormat.dateTime(when)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.neutral,
                    fontWeight:
                        crosshairOn ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 0,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _cell(theme, 'A', c.open, decimals, color),
              _cell(theme, 'Y', c.high, decimals, color),
              _cell(theme, 'D', c.low, decimals, color),
              _cell(theme, 'K', c.close, decimals, color),
              _cell(theme, 'Hacim', c.volume, decimals, AppPalette.neutral,
                  compact: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(
    ThemeData theme,
    String label,
    double? value,
    int dec,
    Color color, {
    bool compact = false,
  }) {
    final text = value == null
        ? TrFormat.noData
        : compact
            ? TrFormat.compact(value)
            : TrFormat.money(value, decimals: dec);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
