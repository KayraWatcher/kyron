import 'dart:math' as math;

import '../../domain/entities/candle.dart';
import '../../domain/technical/indicators.dart';
import '../charts/chart_types.dart';

/// Hesaplanmis gosterge sonucu.
///
/// Tum degerler kaynak mum serisinden **saf matematikle** uretilir.
/// Kaynakta veri yoksa `null` kalir; asla 0 ile doldurulmaz.
class ComputedIndicator {
  const ComputedIndicator({
    required this.config,
    this.line,
    this.lines = const {},
    this.extra = const {},
  });

  final IndicatorConfig config;

  /// Tek degerli gosterge (SMA/EMA/RSI/ATR/OBV...).
  final List<double?>? line;

  /// Coklu seri: Bollinger {upper,middle,lower}, MACD {macd,signal,hist},
  /// Stochastic {k,d}.
  final Map<String, List<double?>> lines;

  /// Panel araligi gibi ek bilgi (orn. MACD histogram rengi icin).
  final Map<String, double> extra;

  /// Bu gosterge ayni seride baska gostergeyle paylasabilir mi?
  bool get sharesMainPlot => config.pane == IndicatorPane.overlay;

  /// Erişilebilir tum tekil seriler (panel cizimi icin).
  Iterable<List<double?>> get allSeries sync* {
    if (line != null) yield line!;
    for (final v in lines.values) {
      yield v;
    }
  }

  /// Seri etiketleri (panel basliginda gosterilir, gercek son deger).
  String summary(String Function(double?) format) {
    if (line != null) {
      final v = _lastValid(line);
      return v == null ? '—' : format(v);
    }
    final parts = <String>[];
    lines.forEach((k, v) {
      final val = _lastValid(v);
      parts.add('$k ${val == null ? '—' : format(val)}');
    });
    return parts.join('  ');
  }

  double? _lastValid(List<double?>? s) {
    if (s == null) return null;
    for (var i = s.length - 1; i >= 0; i--) {
      final v = s[i];
      if (v != null && v.isFinite) return v;
    }
    return null;
  }
}

/// Gosterge hesaplayici - tek giris, tek cikis, yan etkisiz.
abstract final class IndicatorEngine {
  /// Verilen gosterge listesini hesaplar.
  ///
  /// [candles] gorunur serinin tamami olmalidir; sonuclar ayni uzunluktadir.
  static List<ComputedIndicator> compute(
    List<Candle> candles,
    List<IndicatorConfig> configs,
  ) {
    if (candles.isEmpty || configs.isEmpty) return const [];

    final closes = [for (final c in candles) c.close];
    final out = <ComputedIndicator>[];

    for (final cfg in configs) {
      if (!cfg.visible) continue;
      final r = _computeOne(candles, closes, cfg);
      if (r != null) out.add(r);
    }
    return out;
  }

  static ComputedIndicator? _computeOne(
    List<Candle> candles,
    List<double> closes,
    IndicatorConfig cfg,
  ) {
    final p = cfg.params;
    int period(String key, int fallback) {
      final v = p[key];
      if (v == null || !v.isFinite || v < 1) return fallback;
      return v.round().clamp(1, 5000);
    }

    switch (cfg.id) {
      case IndicatorPresets.sma:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.sma(closes, period('period', 20)),
        );
      case IndicatorPresets.ema:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.ema(closes, period('period', 20)),
        );
      case IndicatorPresets.wma:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.wma(closes, period('period', 20)),
        );
      case IndicatorPresets.vwap:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.vwap(candles),
        );
      case IndicatorPresets.rsi:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.rsi(closes, period('period', 14)),
        );
      case IndicatorPresets.macd:
        final s = Indicators.macd(
          closes,
          fast: period('fast', 12),
          slow: period('slow', 26),
          signal: period('signal', 9),
        );
        return ComputedIndicator(config: cfg, lines: {
          'MACD': s.line('MACD') ?? const [],
          'Sinyal': s.line('Sinyal') ?? const [],
          'Histogram': s.line('Histogram') ?? const [],
        });
      case IndicatorPresets.stoch:
        final s = Indicators.stoch(
          candles,
          kPeriod: period('period', 14),
          dPeriod: period('smooth', 3),
        );
        return ComputedIndicator(config: cfg, lines: {
          '%K': s.line('%K') ?? const [],
          '%D': s.line('%D') ?? const [],
        });
      case IndicatorPresets.cci:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.cci(candles, period('period', 20)),
        );
      case IndicatorPresets.williams:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.williamsR(candles, period('period', 14)),
        );
      case IndicatorPresets.bollinger:
        final s = Indicators.bollinger(
          closes,
          period: period('period', 20),
          multiplier: p['dev'] ?? 2,
        );
        return ComputedIndicator(config: cfg, lines: {
          'Üst': s.line('Üst') ?? const [],
          'Orta': s.line('Orta') ?? const [],
          'Alt': s.line('Alt') ?? const [],
        });
      case IndicatorPresets.atr:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.atr(candles, period('period', 14)),
        );
      case IndicatorPresets.volume:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.volume(candles),
        );
      case IndicatorPresets.obv:
        return ComputedIndicator(
          config: cfg,
          line: Indicators.obv(candles),
        );
      default:
        return null;
    }
  }

  /// Panel icin deger araligi (0-100 / dinamik / sifir merkezli).
  static (double min, double max) rangeFor(
    IndicatorPane pane,
    List<ComputedIndicator> items,
  ) {
    switch (pane) {
      case IndicatorPane.oscillator:
        var lo = double.infinity;
        var hi = double.negativeInfinity;
        for (final ci in items) {
          for (final s in ci.allSeries) {
            for (final v in s) {
              if (v == null || !v.isFinite) continue;
              if (v < lo) lo = v;
              if (v > hi) hi = v;
            }
          }
        }
        if (!lo.isFinite || !hi.isFinite) return (0, 100);
        // CCI/ATR gibi gostergeler 0-100 disina cikabilir; araligi genislet.
        lo = math.min(lo, 0);
        hi = math.max(hi, 100);
        return (lo, hi);
      case IndicatorPane.zeroBased:
        var lo = 0.0;
        var hi = 0.0;
        for (final ci in items) {
          for (final s in ci.allSeries) {
            for (final v in s) {
              if (v == null || !v.isFinite) continue;
              if (v < lo) lo = v;
              if (v > hi) hi = v;
            }
          }
        }
        if (lo == hi) return (-1, 1);
        return (lo, hi);
      case IndicatorPane.overlay:
        var lo = double.infinity;
        var hi = double.negativeInfinity;
        for (final ci in items) {
          for (final s in ci.allSeries) {
            for (final v in s) {
              if (v == null || !v.isFinite) continue;
              if (v < lo) lo = v;
              if (v > hi) hi = v;
            }
          }
        }
        if (!lo.isFinite || !hi.isFinite) return (0, 1);
        return (lo, hi);
    }
  }
}
