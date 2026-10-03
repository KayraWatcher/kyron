import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/candle.dart';

/// Grafik gorunur alani ve fiyat-ekran donusumleri.
///
/// Bu sinif **hiçbir fiyat uretmez**; yalnizca verilen mum serisi uzerinde
/// matematiksel bir gorgu (viewport) saglar. Boylece zoom/pan/kirilma
/// islemleri tamamen saf ve test edilebilirdir.
class ChartGeometry {
  ChartGeometry({
    required this.candles,
    required this.viewport,
    required this.plotSize,
    this.axisWidth = 68,
    this.timeAxisHeight = 22,
    this.volumeShare = 0.18,
  });

  /// Tam mum serisi (gorunen degil).
  final List<Candle> candles;

  /// Gorunur aralik.
  final ChartViewport viewport;

  /// Cizim alani (plot) boyutu - zaman ekseni ve fiyat ekseni disinda.
  final Size plotSize;

  /// Sagdaki fiyat etiketi genisligi.
  final double axisWidth;

  /// Alttaki zaman etiketi yuksekligi.
  final double timeAxisHeight;

  /// Hacim alaninin plot'a orani (0..1).
  final double volumeShare;

  // --- X ekseni ---

  int get first => viewport.first;
  int get last => viewport.lastExclusive.clamp(0, candles.length);
  int get count => (last - first).clamp(0, candles.length);

  /// Tek mumun yatay genisligi.
  double get candleWidth => count <= 0 ? 0 : plotSize.width / count;

  /// Dizindeki mumun sol kenarinin X konumu.
  double xOf(int index) => (index - first) * candleWidth;

  /// Mumun merkez X konumu.
  double xCenterOf(int index) => xOf(index) + candleWidth / 2;

  /// Verilen X konumundaki mum dizini.
  int indexOfX(double x) {
    if (count <= 0) return first;
    final i = (x / candleWidth).floor() + first;
    return i.clamp(first, last - 1);
  }

  // --- Y ekseni (fiyat) ---

  double get priceMax => viewport.priceMax;
  double get priceMin => viewport.priceMin;

  double get _priceRange {
    final r = priceMax - priceMin;
    // Ayni fiyat butun seride: dikey cizgi.
    return r.isFinite && r > 0 ? r : 1;
  }

  /// Fiyat -> Y pikseli.
  double yOfPrice(double price) {
    final t = (price - priceMin) / _priceRange;
    return plotSize.height - (t.clamp(0.0, 1.0) * plotSize.height);
  }

  /// Y pikseli -> Fiyat.
  double priceOfY(double y) {
    final t = 1 - (y / plotSize.height.clamp(1, double.infinity));
    return priceMin + t.clamp(0.0, 1.0) * _priceRange;
  }

  /// Hacim bolumunun ust siniri (Y).
  double get volumeTop => plotSize.height * (1 - volumeShare);

  /// Hacim -> Y yuksekligi (0..hacim alani).
  double volumeBarHeight(double volume, double volumeMax) {
    if (volumeMax <= 0 || !volumeMax.isFinite) return 0;
    final h = plotSize.height * volumeShare;
    return (volume / volumeMax).clamp(0.0, 1.0) * h;
  }

  /// Fiyat araligina gore guvenli dikey bolme degeri.
  static List<double> niceTicks(double min, double max, int desired) {
    if (!min.isFinite || !max.isFinite || max <= min) return const [0];
    final raw = (max - min) / math.max(1, desired);
    final mag = math.pow(10, (math.log(raw) / math.ln10).floorToDouble());
    final norm = raw / mag;
    final step = (norm <= 1 ? 1.0 : norm <= 2 ? 2.0 : norm <= 5 ? 5.0 : 10.0) *
        mag;
    final out = <double>[];
    var v = (min / step).ceil() * step;
    while (v <= max + step * 0.001) {
      out.add(double.parse(v.toStringAsFixed(10)));
      v += step;
    }
    return out;
  }
}

/// Pan / zoom icin **tek** gecerli pencere (gorunur aralik) kurallari.
///
/// Grafik suruklenirken pencere asla verinin disina cikmaz:
///
///  * `first` her zaman `[0, n - visible]` araligindadir.
///  * Boylece **sag tarafta bosluk birakilmaz** (son mum sag kenara dayanir)
///    ve **sol tarafta uydurma mum cizilmez**; kullanici tamamen gecmise
///    surukleyebilir.
///  * Gorunur sayi serideki mum sayisini **asla asmaz**; bu ayrica
///    `num.clamp(min, max)` icinde `min > max` olma (RangeError) hatasini
///    da engeller.
///
/// Tum pan/zoom matematigi burada toplanir; boylece saf ve test edilebilir.
class ChartWindow {
  const ChartWindow._();

  /// Ekranda gosterilecek **en az** mum (daha kisa serilerde serinin tamami).
  static const int minVisible = 8;

  /// Ekranda gosterilecek **en fazla** mum.
  static const int maxVisible = 500;

  /// Gorunur mum sayisini serinin uzunluguna gore guvenli sinirlar.
  static int clampVisible(int visible, int n) {
    if (n <= 0) return 0;
    final lo = n < minVisible ? n : minVisible;
    final hi = n < maxVisible ? n : maxVisible;
    if (visible < lo) return lo;
    if (visible > hi) return hi;
    return visible;
  }

  /// Tekerlek / buton ile yaklastirma: yeni gorunur sayi.
  static int zoomVisible({
    required int current,
    required double factor,
    required int n,
  }) {
    if (n <= 0) return 0;
    final cur = clampVisible(current, n);
    return clampVisible((cur * factor).round(), n);
  }

  /// Parmakli olcekleme: yeni gorunur sayi.
  static int scaledVisible({
    required int base,
    required double scale,
    required int n,
  }) {
    if (n <= 0) return 0;
    if (!scale.isFinite || scale <= 0) return clampVisible(base, n);
    return clampVisible((base * scale).round(), n);
  }

  /// Gorunur pencerenin ilk mum indeksini sinirlar.
  ///
  /// Bu fonksiyon "sagda bosluk kalmaz" garantisidir: donen deger her zaman
  /// `first + visible <= n` ve `first >= 0` saglar.
  static int clampFirst(int first, int visible, int n) {
    if (n <= 0) return 0;
    final v = clampVisible(visible, n);
    final maxFirst = n - v;
    if (first < 0) return 0;
    if (first > maxFirst) return maxFirst;
    return first;
  }

  /// Piksel cinsinden [dx] yatay surukleme sonrasi ilk mum indeksi.
  ///
  /// `dx > 0` -> sag surukleme -> daha **eski** mumlar gorunur.
  static int panFirst({
    required int first,
    required double dx,
    required int visible,
    required int n,
    required double plotWidth,
  }) {
    if (n <= 0 || plotWidth <= 0) return clampFirst(first, visible, n);
    final candlesPerPx = clampVisible(visible, n) / plotWidth;
    final delta = (-dx * candlesPerPx).round();
    return clampFirst(first + delta, visible, n);
  }
}

/// Gorunur aralik + fiyat sinirlari.
class ChartViewport {
  const ChartViewport({
    required this.first,
    required this.lastExclusive,
    required this.priceMin,
    required this.priceMax,
  });

  final int first;
  final int lastExclusive;
  final double priceMin;
  final double priceMax;

  int get length => (lastExclusive - first).clamp(0, 1 << 30);

  /// [candles] uzerinde fiyat sinirlarini hesaplar (verilen aralik).
  ///
  /// Eger [fixed] verilirse o fiyat araligi korunur (gosterge icin).
  factory ChartViewport.forRange({
    required List<Candle> candles,
    required int first,
    required int lastExclusive,
    double? min,
    double? max,
    double paddingRatio = 0.08,
  }) {
    final safeFirst = first.clamp(0, candles.length);
    final safeLast = lastExclusive.clamp(safeFirst, candles.length);

    double lo;
    double hi;

    if (min != null && max != null && min.isFinite && max.isFinite && max > min) {
      lo = min;
      hi = max;
    } else {
      lo = double.infinity;
      hi = double.negativeInfinity;
      for (var i = safeFirst; i < safeLast; i++) {
        final c = candles[i];
        final lows = c.low;
        final highs = c.high;
        if (lows.isFinite) lo = math.min(lo, lows);
        if (highs.isFinite) hi = math.max(hi, highs);
      }
      if (!lo.isFinite || !hi.isFinite) {
        // Seride anlamli deger yok: sahte deger uretilmez, 0-1 araligi verilir.
        lo = 0;
        hi = 1;
      }
    }

    final range = hi - lo;
    final pad = (range > 0 ? range : hi.abs().clamp(1, double.infinity)) *
        paddingRatio;

    return ChartViewport(
      first: safeFirst,
      lastExclusive: safeLast,
      priceMin: lo - pad,
      priceMax: hi + pad,
    );
  }

  ChartViewport copyWith({
    int? first,
    int? lastExclusive,
    double? priceMin,
    double? priceMax,
  }) {
    return ChartViewport(
      first: first ?? this.first,
      lastExclusive: lastExclusive ?? this.lastExclusive,
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
    );
  }

  /// Deger bazli esitlik: ayni pencere degeri her build'de **yeni** nesne
  /// olarak uretilir; `shouldRepaint` bu yuzden deger karsilastirmasi ister.
  @override
  bool operator ==(Object other) =>
      other is ChartViewport &&
      other.first == first &&
      other.lastExclusive == lastExclusive &&
      other.priceMin == priceMin &&
      other.priceMax == priceMax;

  @override
  int get hashCode => Object.hash(first, lastExclusive, priceMin, priceMax);
}
