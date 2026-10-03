import 'dart:math' as math;

import '../entities/candle.dart';

/// Teknik gosterge ciktilari.
///
/// Her seri, giris dizisi ile ayni uzunluktadir ve **asla null icermez**;
/// hesaplanamayan on elemanlar `double.nan` yerine `[double.nan]` yerine
/// baslangicta bos birakilir. [IndicatorSeries.values] ayni uzunluktadir,
/// hesaplanamayan indekslerde `null` icerir - boylece UI "—" gosterir.
class IndicatorSeries {
  const IndicatorSeries({required this.name, required this.values});

  final String name;

  /// Girdi dizisi ile ayni uzunlukta; hesaplama mumkun olmayan yerler null.
  final List<double?> values;

  double? get last {
    for (int i = values.length - 1; i >= 0; i--) {
      final v = values[i];
      if (v != null) return v;
    }
    return null;
  }

  int get length => values.length;
}

/// Cok cizgili gosterge (Bollinger 3 bant, MACD 3 cizgi, Stochastic 2 ...).
class MultiIndicatorSeries {
  const MultiIndicatorSeries({required this.name, required this.lines});

  final String name;

  /// Her cizgi ayni uzunlukta.
  final Map<String, List<double?>> lines;

  List<double?>? line(String key) => lines[key];
}

/// Tum teknik gosterge hesaplamalari - saf Dart, Flutter'a bagimli degil.
///
/// Boylece birebir unit test yazilabilir ve grafik motoruyla paylasilir.
abstract final class Indicators {
  // ---------------------------------------------------------------------------
  // TREND
  // ---------------------------------------------------------------------------

  /// Basit hareketli ortalama.
  static List<double?> sma(List<double> source, int period) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0) return out;
    double sum = 0;
    for (int i = 0; i < source.length; i++) {
      sum += source[i];
      if (i >= period) sum -= source[i - period];
      if (i >= period - 1) {
        final v = sum / period;
        out[i] = v.isFinite ? v : null;
      }
    }
    return out;
  }

  /// Ustel hareketli ortalama. [seed] verilirse ilk deger on tanimli olur.
  static List<double?> ema(List<double> source, int period, {double? seed}) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0 || source.isEmpty) return out;
    final k = 2 / (period + 1);

    if (seed != null && seed.isFinite) {
      double prev = seed;
      for (int i = 0; i < source.length; i++) {
        prev = source[i] * k + prev * (1 - k);
        out[i] = prev.isFinite ? prev : null;
      }
      return out;
    }

    // Ilk EMA = ilk `period` degerin basit ortalamasi.
    if (source.length < period) return out;
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += source[i];
    }
    double prev = sum / period;
    out[period - 1] = prev;
    for (int i = period; i < source.length; i++) {
      prev = source[i] * k + prev * (1 - k);
      out[i] = prev.isFinite ? prev : null;
    }
    return out;
  }

  /// Agirlikli hareketli ortalama.
  static List<double?> wma(List<double> source, int period) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0) return out;
    final denom = period * (period + 1) / 2;
    for (int i = period - 1; i < source.length; i++) {
      double sum = 0;
      for (int j = 0; j < period; j++) {
        sum += source[i - j] * (period - j);
      }
      final v = sum / denom;
      out[i] = v.isFinite ? v : null;
    }
    return out;
  }

  /// Hacim agirlikli ortalama (VWAP). [timestamps] kullanilmaz;
  /// standart mum bazli hesaplama yapilir.
  static List<double?> vwap(List<Candle> candles) {
    final out = List<double?>.filled(candles.length, null);
    double cumTpVol = 0;
    double cumVol = 0;
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final tp = (c.high + c.low + c.close) / 3;
      final v = c.volume ?? 0;
      if (v > 0) {
        cumTpVol += tp * v;
        cumVol += v;
      }
      if (cumVol > 0) {
        final value = cumTpVol / cumVol;
        out[i] = value.isFinite ? value : null;
      }
    }
    return out;
  }

  /// Hareketli ortalama cizgisi uretimi (SMA veya EMA).
  static List<double?> movingAverage(
    List<Candle> candles, {
    required int period,
    required bool exponential,
  }) {
    final closes = [for (final c in candles) c.close];
    return exponential ? ema(closes, period) : sma(closes, period);
  }

  // ---------------------------------------------------------------------------
  // MOMENTUM
  // ---------------------------------------------------------------------------

  /// RSI - Wilder yumusaklasma. [period] varsayilan 14.
  static List<double?> rsi(List<double> source, int period) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0 || source.length <= period) return out;

    double gain = 0;
    double loss = 0;
    for (int i = 1; i <= period; i++) {
      final d = source[i] - source[i - 1];
      if (d >= 0) {
        gain += d;
      } else {
        loss -= d;
      }
    }
    double avgGain = gain / period;
    double avgLoss = loss / period;
    out[period] = _rsiValue(avgGain, avgLoss);

    for (int i = period + 1; i < source.length; i++) {
      final d = source[i] - source[i - 1];
      final g = d > 0 ? d : 0.0;
      final l = d < 0 ? -d : 0.0;
      avgGain = (avgGain * (period - 1) + g) / period;
      avgLoss = (avgLoss * (period - 1) + l) / period;
      out[i] = _rsiValue(avgGain, avgLoss);
    }
    return out;
  }

  static double? _rsiValue(double avgGain, double avgLoss) {
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    final v = 100 - (100 / (1 + rs));
    return v.isFinite ? v : null;
  }

  /// MACD -> {macd, signal, histogram}.
  static MultiIndicatorSeries macd(
    List<double> source, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    final n = source.length;
    final fastEma = ema(source, fast);
    final slowEma = ema(source, slow);

    final macdLine = List<double?>.filled(n, null);
    for (int i = 0; i < n; i++) {
      final f = fastEma[i];
      final s = slowEma[i];
      if (f == null || s == null) continue;
      final v = f - s;
      macdLine[i] = v.isFinite ? v : null;
    }

    // Signal, MACD degerlerinin EMA'si (baslangictaki null degerler atlanir).
    final signalLine = _emaOverNullable(macdLine, signal);
    final histogram = List<double?>.filled(n, null);
    for (int i = 0; i < n; i++) {
      final m = macdLine[i];
      final s = signalLine[i];
      if (m == null || s == null) continue;
      final v = m - s;
      histogram[i] = v.isFinite ? v : null;
    }

    return MultiIndicatorSeries(
      name: 'MACD',
      lines: {'MACD': macdLine, 'Sinyal': signalLine, 'Histogram': histogram},
    );
  }

  /// Null iceren seri uzerinde EMA (null degerler es gecilir).
  static List<double?> _emaOverNullable(List<double?> source, int period) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0) return out;
    final k = 2 / (period + 1);

    int seedCount = 0;
    double seedSum = 0;
    int seedEnd = -1;
    for (int i = 0; i < source.length; i++) {
      final v = source[i];
      if (v == null) continue;
      seedSum += v;
      seedCount++;
      if (seedCount == period) {
        seedEnd = i;
        break;
      }
    }
    if (seedEnd < 0) return out;

    double prev = seedSum / period;
    out[seedEnd] = prev;
    for (int i = seedEnd + 1; i < source.length; i++) {
      final v = source[i];
      if (v == null) continue;
      prev = v * k + prev * (1 - k);
      out[i] = prev.isFinite ? prev : null;
    }
    return out;
  }

  /// Stochastic -> {K, D}.
  static MultiIndicatorSeries stoch(
    List<Candle> candles, {
    int kPeriod = 14,
    int dPeriod = 3,
  }) {
    final n = candles.length;
    final kRaw = List<double?>.filled(n, null);

    for (int i = kPeriod - 1; i < n; i++) {
      double highest = candles[i].high;
      double lowest = candles[i].low;
      for (int j = i - kPeriod + 1; j <= i; j++) {
        if (candles[j].high > highest) highest = candles[j].high;
        if (candles[j].low < lowest) lowest = candles[j].low;
      }
      final range = highest - lowest;
      if (range <= 0) {
        kRaw[i] = 50;
        continue;
      }
      final v = (candles[i].close - lowest) / range * 100;
      kRaw[i] = v.isFinite ? v : null;
    }

    // K, 3 periyot SMA ile yumusatilir (standart).
    final kLine = _smaNullable(kRaw, 3);
    final dLine = _smaNullable(kLine, dPeriod);

    return MultiIndicatorSeries(
      name: 'Stokastik',
      lines: {'%K': kLine, '%D': dLine},
    );
  }

  /// CCI - Emtia Kanal Endeksi.
  static List<double?> cci(List<Candle> candles, int period) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (period <= 0) return out;

    final tp = [
      for (final c in candles) (c.high + c.low + c.close) / 3,
    ];

    for (int i = period - 1; i < n; i++) {
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += tp[j];
      }
      final smaTp = sum / period;
      double dev = 0;
      for (int j = i - period + 1; j <= i; j++) {
        dev += (tp[j] - smaTp).abs();
      }
      final meanDev = dev / period;
      if (meanDev == 0) {
        out[i] = 0;
        continue;
      }
      final v = (tp[i] - smaTp) / (0.015 * meanDev);
      out[i] = v.isFinite ? v : null;
    }
    return out;
  }

  /// Williams %R.
  static List<double?> williamsR(List<Candle> candles, int period) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (period <= 0) return out;
    for (int i = period - 1; i < n; i++) {
      double highest = candles[i].high;
      double lowest = candles[i].low;
      for (int j = i - period + 1; j <= i; j++) {
        if (candles[j].high > highest) highest = candles[j].high;
        if (candles[j].low < lowest) lowest = candles[j].low;
      }
      final range = highest - lowest;
      if (range <= 0) {
        out[i] = -50;
        continue;
      }
      final v = -100 * (highest - candles[i].close) / range;
      out[i] = v.isFinite ? v : null;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // VOLATILITE
  // ---------------------------------------------------------------------------

  /// Bollinger Bantlari -> {orta, ust, alt}.
  static MultiIndicatorSeries bollinger(
    List<double> source, {
    int period = 20,
    double multiplier = 2,
  }) {
    final mid = sma(source, period);
    final upper = List<double?>.filled(source.length, null);
    final lower = List<double?>.filled(source.length, null);

    for (int i = period - 1; i < source.length; i++) {
      final m = mid[i];
      if (m == null) continue;
      double sumSq = 0;
      for (int j = i - period + 1; j <= i; j++) {
        final d = source[j] - m;
        sumSq += d * d;
      }
      final sd = (sumSq / period);
      if (sd < 0) continue;
      final std = math.sqrt(sd);
      final u = m + multiplier * std;
      final l = m - multiplier * std;
      upper[i] = u.isFinite ? u : null;
      lower[i] = l.isFinite ? l : null;
    }

    return MultiIndicatorSeries(
      name: 'Bollinger',
      lines: {'Üst': upper, 'Orta': mid, 'Alt': lower},
    );
  }

  /// ATR - Wilder.
  static List<double?> atr(List<Candle> candles, int period) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (period <= 0 || n == 0) return out;

    final tr = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final c = candles[i];
      if (i == 0) {
        tr[i] = c.range;
        continue;
      }
      final prevClose = candles[i - 1].close;
      final a = c.high - c.low;
      final b = (c.high - prevClose).abs();
      final d = (c.low - prevClose).abs();
      tr[i] = [a, b, d].reduce((x, y) => x > y ? x : y);
    }

    if (n < period) return out;
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += tr[i];
    }
    double prev = sum / period;
    out[period - 1] = prev.isFinite ? prev : null;
    for (int i = period; i < n; i++) {
      prev = (prev * (period - 1) + tr[i]) / period;
      out[i] = prev.isFinite ? prev : null;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // HACIM
  // ---------------------------------------------------------------------------

  /// OBV - On Balance Volume.
  static List<double?> obv(List<Candle> candles) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (n == 0) return out;
    double running = 0;
    out[0] = 0;
    for (int i = 1; i < n; i++) {
      final v = candles[i].volume;
      final prevClose = candles[i - 1].close;
      if (v != null) {
        if (candles[i].close > prevClose) {
          running += v;
        } else if (candles[i].close < prevClose) {
          running -= v;
        }
      }
      out[i] = running;
    }
    return out;
  }

  /// Basit hacim serisi (mumlarin volume degerleri).
  static List<double?> volume(List<Candle> candles) =>
      [for (final c in candles) c.volume];

  // ---------------------------------------------------------------------------
  // YARDIMCILAR
  // ---------------------------------------------------------------------------

  /// Null iceren seri uzerinde SMA. Kesintisiz `period` adet dolu deger
  /// goruldugunde cikti uretmeye baslar; null degerler hesaplamaya girmez
  /// ama seri boyunca kaydirma noktalarini korur.
  static List<double?> _smaNullable(List<double?> source, int period) {
    final out = List<double?>.filled(source.length, null);
    if (period <= 0) return out;

    int streak = 0;
    double sum = 0;
    for (int i = 0; i < source.length; i++) {
      final v = source[i];
      if (v == null) {
        streak = 0;
        sum = 0;
        continue;
      }
      sum += v;
      streak++;
      if (streak > period) {
        // Ilk fazla degeri dusur.
        final start = i - streak + 1;
        sum -= source[start]!;
        streak = period;
      }
      if (streak == period) {
        final avg = sum / period;
        out[i] = avg.isFinite ? avg : null;
      }
    }
    return out;
  }
}
