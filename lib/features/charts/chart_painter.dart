import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/candle.dart';
import 'chart_geometry.dart';
import 'chart_types.dart';
import 'drawing.dart';
import 'indicator_engine.dart';

/// Alt panel (RSI/MACD/Hacim vb.) icin cizim verisi.
class ChartPanel {
  const ChartPanel({required this.title, required this.items});

  final String title;
  final List<ComputedIndicator> items;

  (double, double) get range => IndicatorEngine.rangeFor(
        items.isEmpty ? IndicatorPane.oscillator : items.first.config.pane,
        items,
      );

  @override
  bool operator ==(Object other) =>
      other is ChartPanel &&
      other.title == title &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(items));
}

/// Cizimciya gecilen tum veriler (salt, degismez).
class ChartRenderData {
  const ChartRenderData({
    required this.candles,
    required this.viewport,
    required this.chartType,
    this.overlays = const [],
    this.panels = const [],
    this.drawings = const [],
    this.incompleteDrawing,
    this.crosshair,
    this.crosshairIndex,
    this.crosshairPrice,
    this.showVolume = true,
    this.showGrid = true,
    this.showLastPrice = true,
    this.showTimeAxis = true,
    this.decimals,
    this.priceFormatter,
    required this.colors,
  });

  final List<Candle> candles;
  final ChartViewport viewport;
  final ChartType chartType;

  /// Ana grafikte cizilen gostergeler.
  final List<ComputedIndicator> overlays;

  /// Alt paneller.
  final List<ChartPanel> panels;

  final List<Drawing> drawings;
  final Drawing? incompleteDrawing;

  final Offset? crosshair;
  final int? crosshairIndex;
  final double? crosshairPrice;

  final bool showVolume;
  final bool showGrid;
  final bool showLastPrice;
  final bool showTimeAxis;

  /// Fiyat basamak sayisi (varliga gore).
  final int? decimals;
  final String Function(double)? priceFormatter;

  final ChartColors colors;
}

/// Tema bagimli renk seti.
class ChartColors {
  const ChartColors({
    required this.up,
    required this.down,
    required this.grid,
    required this.axisText,
    required this.crosshair,
    required this.panelBg,
    required this.lastPrice,
    required this.surface,
  });

  final Color up;
  final Color down;
  final Color grid;
  final Color axisText;
  final Color crosshair;
  final Color panelBg;
  final Color lastPrice;
  final Color surface;

  factory ChartColors.fromTheme(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return ChartColors(
      up: const Color(0xFF12A150),
      down: const Color(0xFFF04438),
      grid: dark ? const Color(0xFF1C2432) : const Color(0xFFEDEFF3),
      axisText: dark ? const Color(0xFF7A8699) : const Color(0xFF7C879B),
      crosshair: dark ? const Color(0xFF8A94A6) : const Color(0xFF667085),
      panelBg: Colors.transparent,
      lastPrice: const Color(0xFFD4A017),
      surface: theme.scaffoldBackgroundColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChartColors &&
      other.up == up &&
      other.down == down &&
      other.grid == grid &&
      other.axisText == axisText &&
      other.crosshair == crosshair &&
      other.panelBg == panelBg &&
      other.lastPrice == lastPrice &&
      other.surface == surface;

  @override
  int get hashCode =>
      Object.hash(up, down, grid, axisText, crosshair, panelBg, lastPrice, surface);
}

/// Grafigin tamamini cizmekten sorumlu painter.
///
/// Sahipleri: mumlar, gostergeler, cizimler, capraz imleç. Hiçbir veriyi
/// **uretmez** - yalnizca verilen veriyi ekrana isler.
class ChartPainter extends CustomPainter {
  ChartPainter(this.data);

  final ChartRenderData data;

  static const double priceAxisWidth = 70;
  static const double timeAxisHeight = 22;
  static const double panelHeight = 78;
  static const double panelGap = 4;

  @override
  bool shouldRepaint(covariant ChartPainter old) {
    // Yalnizca **gorsel olarak degisen** verilerde repaint tetiklenir.
    // Boylece ayni degerlerle yeniden kurulan bir ust agac (imlec her
    // hareketinde olusan yeni ChartViewport/ChartColors nesneleri gibi)
    // gereksiz boyama yapmaz; liste karsilastirmalari icerik bazlidir.
    final a = old.data;
    final b = data;
    return a.crosshair != b.crosshair ||
        a.crosshairIndex != b.crosshairIndex ||
        a.crosshairPrice != b.crosshairPrice ||
        !listEquals(a.candles, b.candles) ||
        a.viewport != b.viewport ||
        !listEquals(a.overlays, b.overlays) ||
        !listEquals(a.panels, b.panels) ||
        !listEquals(a.drawings, b.drawings) ||
        a.incompleteDrawing != b.incompleteDrawing ||
        a.chartType != b.chartType ||
        a.showVolume != b.showVolume ||
        a.showGrid != b.showGrid ||
        a.showLastPrice != b.showLastPrice ||
        a.showTimeAxis != b.showTimeAxis ||
        a.decimals != b.decimals ||
        a.priceFormatter != b.priceFormatter ||
        a.colors != b.colors;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = data.colors;
    final totalPanelH =
        data.panels.isEmpty ? 0.0 : data.panels.length * (panelHeight + panelGap);

    final plotSize = Size(
      math.max(0, size.width - priceAxisWidth),
      math.max(0, size.height - timeAxisHeight - totalPanelH),
    );

    if (plotSize.width <= 0 || plotSize.height <= 0) return;

    final geo = ChartGeometry(
      candles: data.candles,
      viewport: data.viewport,
      plotSize: plotSize,
      axisWidth: priceAxisWidth,
      timeAxisHeight: timeAxisHeight,
      volumeShare: 0.16,
    );

    if (geo.count <= 0) return;

    // 1) Izgara
    if (data.showGrid) _paintGrid(canvas, geo, c);

    // 2) Ana seri
    _paintMainSeries(canvas, geo, c);

    // 3) Ust gostergeler
    _paintOverlays(canvas, geo, c);

    // 4) Cizimler
    _paintDrawings(canvas, geo, c);

    // 5) Alt paneller
    _paintPanels(canvas, size, geo, plotSize, c);

    // 6) Son fiyat cizgisi
    if (data.showLastPrice) _paintLastPrice(canvas, geo, c);

    // 7) Fiyat ekseni
    _paintPriceAxis(canvas, size, geo, plotSize, c);

    // 8) Zaman ekseni
    if (data.showTimeAxis) {
      _paintTimeAxis(canvas, size, plotSize, geo, c);
    }

    // 9) Capraz imlec (en ustte)
    if (data.crosshair != null) _paintCrosshair(canvas, size, plotSize, geo, c);

    // 10) Kenarlik
    final border = Paint()
      ..color = c.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(plotSize.width, 0, priceAxisWidth, size.height),
      border,
    );
    canvas.drawLine(
      Offset(0, plotSize.height),
      Offset(size.width, plotSize.height),
      border,
    );
  }

  // --------------------------------------------------------------------------
  // Izgara
  // --------------------------------------------------------------------------

  void _paintGrid(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final paint = Paint()
      ..color = c.grid
      ..strokeWidth = 1;

    final ticks = ChartGeometry.niceTicks(geo.priceMin, geo.priceMax, 5);
    for (final t in ticks) {
      final y = geo.yOfPrice(t);
      if (y < 0 || y > geo.plotSize.height) continue;
      canvas.drawLine(Offset(0, y), Offset(geo.plotSize.width, y), paint);
    }

    final xTicks = _timeTickCount(geo);
    final step = (geo.count / xTicks).ceilToDouble();
    for (var i = 0; i < geo.count; i += step.toInt().clamp(1, 1 << 20)) {
      final x = geo.xCenterOf(geo.first + i);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, geo.plotSize.height),
        paint,
      );
    }
  }

  int _timeTickCount(ChartGeometry geo) =>
      (geo.plotSize.width / 90).ceil().clamp(2, 20);

  // --------------------------------------------------------------------------
  // Ana seri
  // --------------------------------------------------------------------------

  void _paintMainSeries(Canvas canvas, ChartGeometry geo, ChartColors c) {
    switch (data.chartType) {
      case ChartType.volume:
        _paintVolumeOnly(canvas, geo, c);
        return;
      case ChartType.candlestick:
      case ChartType.heikinAshi:
        _paintCandles(canvas, geo, c);
        return;
      case ChartType.ohlc:
        _paintOhlc(canvas, geo, c);
        return;
      case ChartType.line:
        _paintLine(canvas, geo, c, fill: false);
        return;
      case ChartType.area:
        _paintLine(canvas, geo, c, fill: true);
        return;
    }
  }

  void _paintCandles(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final bodyPaint = Paint()..style = PaintingStyle.fill;
    final wickPaint = Paint()..strokeWidth = 1;

    final cw = geo.candleWidth;
    final bodyW = (cw * 0.66).clamp(1.0, 20.0);
    final half = bodyW / 2;

    for (var i = geo.first; i < geo.last; i++) {
      final k = geo.candles[i];
      final x = geo.xCenterOf(i);
      final isUp = k.isBullish;
      final color = isUp ? c.up : c.down;

      bodyPaint.color = color;
      wickPaint.color = color;

      // Fitil
      canvas.drawLine(
        Offset(x, geo.yOfPrice(k.high)),
        Offset(x, geo.yOfPrice(k.low)),
        wickPaint,
      );

      // Govde
      final yOpen = geo.yOfPrice(k.open);
      final yClose = geo.yOfPrice(k.close);
      final top = math.min(yOpen, yClose);
      final h = (yClose - yOpen).abs().clamp(0.5, double.infinity);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - half, top, bodyW, h),
          const Radius.circular(1),
        ),
        bodyPaint,
      );
    }
  }

  void _paintOhlc(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final p = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.butt;

    final cw = geo.candleWidth;
    final arm = (cw * 0.36).clamp(1.0, 12.0);

    for (var i = geo.first; i < geo.last; i++) {
      final k = geo.candles[i];
      final x = geo.xCenterOf(i);
      final color = k.isBullish ? c.up : c.down;
      p.color = color;

      final yo = geo.yOfPrice(k.open);
      final yc = geo.yOfPrice(k.close);
      final yh = geo.yOfPrice(k.high);
      final yl = geo.yOfPrice(k.low);

      canvas.drawLine(Offset(x, yh), Offset(x, yl), p);
      canvas.drawLine(Offset(x - arm, yo), Offset(x, yo), p);
      canvas.drawLine(Offset(x, yc), Offset(x + arm, yc), p);
    }
  }

  void _paintLine(Canvas canvas, ChartGeometry geo, ChartColors c,
      {required bool fill}) {
    final path = Path();
    final color = _trendColor(c);

    var started = false;
    for (var i = geo.first; i < geo.last; i++) {
      final close = geo.candles[i].close;
      if (!close.isFinite) continue;
      final x = geo.xCenterOf(i);
      final y = geo.yOfPrice(close);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (!started) return;

    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(geo.xCenterOf(geo.last - 1), geo.plotSize.height)
        ..lineTo(geo.xCenterOf(geo.first), geo.plotSize.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(0, 0, geo.plotSize.width,
              geo.plotSize.height))
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintVolumeOnly(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final p = Paint()..style = PaintingStyle.fill;
    final maxV = _maxVolume(geo);
    if (maxV <= 0) return;

    for (var i = geo.first; i < geo.last; i++) {
      final v = geo.candles[i].volume;
      if (v == null || !v.isFinite || v <= 0) continue;
      final h = geo.volumeBarHeight(v, maxV);
      if (h <= 0) continue;
      p.color = (geo.candles[i].isBullish ? c.up : c.down)
          .withValues(alpha: 0.75);
      final x = geo.xCenterOf(i);
      final w = (geo.candleWidth * 0.7).clamp(1.0, 30.0);
      canvas.drawRect(
        Rect.fromLTWH(x - w / 2, geo.plotSize.height - h, w, h),
        p,
      );
    }
  }

  double _maxVolume(ChartGeometry geo) {
    var m = 0.0;
    for (var i = geo.first; i < geo.last; i++) {
      final v = geo.candles[i].volume;
      if (v != null && v.isFinite && v > m) m = v;
    }
    return m;
  }

  Color _trendColor(ChartColors c) {
    if (data.candles.isEmpty) return c.lastPrice;
    final visible = [
      for (var i = geoSafeFirst; i < geoSafeLast; i++) data.candles[i],
    ];
    if (visible.isEmpty) return c.lastPrice;
    final first = visible.first.close;
    final last = visible.last.close;
    if (!first.isFinite || !last.isFinite) return c.lastPrice;
    return last >= first ? c.up : c.down;
  }

  int get geoSafeFirst => data.viewport.first.clamp(0, data.candles.length);
  int get geoSafeLast =>
      data.viewport.lastExclusive.clamp(geoSafeFirst, data.candles.length);

  // --------------------------------------------------------------------------
  // Ust gostergeler
  // --------------------------------------------------------------------------

  void _paintOverlays(Canvas canvas, ChartGeometry geo, ChartColors c) {
    if (data.overlays.isEmpty) return;

    for (final ci in data.overlays) {
      final colors = _seriesColors(ci, c);
      var idx = 0;

      if (ci.line != null) {
        _drawSeries(
          canvas,
          geo,
          ci.line!,
          colors[0],
          1.4,
        );
        idx = 1;
      }

      ci.lines.forEach((key, series) {
        final color = colors[idx % colors.length];
        idx++;
        if (ci.config.id == IndicatorPresets.bollinger && key == 'Orta') {
          _drawSeries(canvas, geo, series, color, 1.0, dash: true);
        } else if (ci.config.id == IndicatorPresets.macd && key == 'Histogram') {
          _drawHistogram(canvas, geo, series, c);
        } else {
          _drawSeries(canvas, geo, series, color, 1.4);
        }
      });
    }
  }

  void _drawSeries(
    Canvas canvas,
    ChartGeometry geo,
    List<double?> series,
    Color color,
    double width, {
    bool dash = false,
  }) {
    if (series.length != data.candles.length) return;

    final path = Path();
    var started = false;
    for (var i = geo.first; i < geo.last && i < series.length; i++) {
      final v = series[i];
      if (v == null || !v.isFinite) {
        // Veri yoksa kir; cizgi kaynagi uydurmaz.
        started = false;
        continue;
      }
      final x = geo.xCenterOf(i);
      final y = geo.yOfPrice(v);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (!started) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeCap = dash ? StrokeCap.butt : StrokeCap.round,
    );
  }

  void _drawHistogram(
      Canvas canvas, ChartGeometry geo, List<double?> series, ChartColors c) {
    if (series.length != data.candles.length) return;
    final p = Paint()..style = PaintingStyle.fill;
    final zeroY = geo.yOfPrice(0).clamp(0.0, geo.plotSize.height);
    final w = (geo.candleWidth * 0.5).clamp(1.0, 12.0);

    for (var i = geo.first; i < geo.last && i < series.length; i++) {
      final v = series[i];
      if (v == null || !v.isFinite) continue;
      final y = geo.yOfPrice(v);
      p.color = v >= 0
          ? c.up.withValues(alpha: 0.7)
          : c.down.withValues(alpha: 0.7);
      final top = math.min(y, zeroY);
      final h = (y - zeroY).abs();
      if (h <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(geo.xCenterOf(i) - w / 2, top, w, h),
        p,
      );
    }
  }

  List<Color> _seriesColors(ComputedIndicator ci, ChartColors c) {
    final custom = ci.config.color;
    if (custom != null) {
      return [custom, custom, custom, custom, custom];
    }
    return const [
      Color(0xFF3B82F6),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFF06B6D4),
      Color(0xFFEC4899),
    ];
  }

  // --------------------------------------------------------------------------
  // Cizimler
  // --------------------------------------------------------------------------

  void _paintDrawings(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final all = [
      ...data.drawings,
      if (data.incompleteDrawing != null) data.incompleteDrawing!,
    ];
    if (all.isEmpty) return;

    for (final d in all) {
      switch (d.type) {
        case DrawingTool.hLine:
          if (d.points.isEmpty) break;
          _hLine(canvas, geo, c, d.points.first.price, d.label);
        case DrawingTool.vLine:
          if (d.points.isEmpty) break;
          final x = geo.xCenterOf(d.points.first.index.clamp(0, data.candles.length - 1));
          _stroke(canvas, c.crosshair, Offset(x, 0), Offset(x, geo.plotSize.height), dash: true);
        case DrawingTool.supportResistance:
          if (d.points.isEmpty) break;
          _hLine(canvas, geo, c, d.points.first.price, d.label);
        case DrawingTool.trendLine:
        case DrawingTool.measure:
          if (d.points.length < 2) break;
          _stroke(
            canvas,
            c.crosshair,
            _pt(geo, d.points[0]),
            _pt(geo, d.points[1]),
            dash: d.type == DrawingTool.measure,
          );
        case DrawingTool.channel:
          if (d.points.length < 3) break;
          _stroke(canvas, c.crosshair, _pt(geo, d.points[0]), _pt(geo, d.points[1]));
          _stroke(canvas, c.crosshair, _pt(geo, d.points[2]),
              Offset(_pt(geo, d.points[1]).dx, _pt(geo, d.points[1]).dy -
                  (_pt(geo, d.points[0]).dy - _pt(geo, d.points[1]).dy)));
          _stroke(canvas, c.crosshair.withValues(alpha: 0.6),
              _pt(geo, d.points[0]), _pt(geo, d.points[2]), dash: true);
          break;
        case DrawingTool.fibRetracement:
          if (d.points.length < 2) break;
          _fib(canvas, geo, c, d.points[0].price, d.points[1].price,
              kFibRetracementLevels, fibRetracementPrices(d));
        case DrawingTool.fibExtension:
          if (d.points.length < 3) break;
          final prices = fibExtensionPrices(d);
          _fib(canvas, geo, c, d.points[1].price, d.points[2].price,
              kFibExtensionLevels, prices);
          _stroke(canvas, c.crosshair.withValues(alpha: 0.5),
              _pt(geo, d.points[0]), _pt(geo, d.points[1]), dash: true);
          _stroke(canvas, c.crosshair.withValues(alpha: 0.5),
              _pt(geo, d.points[1]), _pt(geo, d.points[2]), dash: true);
          break;
        case DrawingTool.none:
          break;
      }
    }
  }

  Offset _pt(ChartGeometry geo, DrawingPoint p) {
    final i = p.index.clamp(0, data.candles.length - 1);
    return Offset(geo.xCenterOf(i), geo.yOfPrice(p.price));
  }

  void _hLine(Canvas canvas, ChartGeometry geo, ChartColors c, double price,
      String? label) {
    final y = geo.yOfPrice(price);
    if (y < -1 || y > geo.plotSize.height + 1) return;
    _stroke(canvas, c.crosshair, Offset(0, y), Offset(geo.plotSize.width, y));
    if (label != null && label.isNotEmpty) {
      _tag(canvas, label, Offset(4, y - 16), c.crosshair);
    }
  }

  void _stroke(Canvas canvas, Color color, Offset a, Offset b,
      {bool dash = false}) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (!dash) {
      canvas.drawLine(a, b, p);
      return;
    }
    const seg = 6.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final start = a + dir * t;
      final end = a + dir * math.min(t + seg, total);
      canvas.drawLine(start, end, p);
      t += seg * 2;
    }
  }

  void _fib(Canvas canvas, ChartGeometry geo, ChartColors c, double a, double b,
      List<double> levels, List<double> prices) {
    const color = Color(0xFF8B5CF6);
    for (var i = 0; i < prices.length; i++) {
      final price = prices[i];
      final y = geo.yOfPrice(price);
      if (y < -1 || y > geo.plotSize.height + 1) continue;
      final isKey = levels[i] == 0 || levels[i] == 1;
      _stroke(
        canvas,
        color.withValues(alpha: isKey ? 0.9 : 0.55),
        Offset(0, y),
        Offset(geo.plotSize.width, y),
        dash: !isKey,
      );
      final pct = (levels[i] * 100);
      final txt = pct == pct.roundToDouble()
          ? pct.round().toString()
          : pct.toStringAsFixed(1);
      _tag(canvas, '$txt%  ${_fmt(price)}', Offset(geo.plotSize.width - 96, y - 15),
          color);
    }
  }

  void _tag(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, tp.width + 8, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      r,
      Paint()..color = const Color(0xFF101828).withValues(alpha: 0.72),
    );
    tp.paint(canvas, Offset(at.dx + 4, at.dy + 2));
  }

  String _fmt(double v) {
    final f = data.priceFormatter;
    if (f != null) return f(v);
    final d = data.decimals ?? 2;
    return v.toStringAsFixed(d);
  }

  // --------------------------------------------------------------------------
  // Alt paneller
  // --------------------------------------------------------------------------

  void _paintPanels(Canvas canvas, Size size, ChartGeometry geo,
      Size plotSize, ChartColors c) {
    if (data.panels.isEmpty) return;

    var top = plotSize.height + panelGap;
    for (final panel in data.panels) {
      final rect = Rect.fromLTWH(0, top, plotSize.width, panelHeight);

      canvas.drawRect(
        rect,
        Paint()..color = c.surface.withValues(alpha: 0.35),
      );

      final (lo, hi) = panel.range;
      final pgeo = ChartGeometry(
        candles: data.candles,
        viewport: data.viewport,
        plotSize: Size(plotSize.width, panelHeight),
      );

      // Panel izgarasi + etiketler
      final gridPaint = Paint()
        ..color = c.grid
        ..strokeWidth = 1;
      final mid = _panelY(0, lo, hi, panelHeight);
      if (mid.isFinite && mid >= 0 && mid <= panelHeight) {
        canvas.drawLine(
          Offset(0, top + mid),
          Offset(plotSize.width, top + mid),
          gridPaint,
        );
      }

      for (final ci in panel.items) {
        final colors = _seriesColors(ci, c);
        var idx = 0;
        if (ci.line != null) {
          _drawSeriesInPanel(canvas, pgeo, top, lo, hi, ci.line!, colors[0]);
          idx = 1;
        }
        ci.lines.forEach((key, series) {
          final color = colors[idx % colors.length];
          idx++;
          if (ci.config.id == IndicatorPresets.macd && key == 'Histogram') {
            _histogramInPanel(canvas, pgeo, top, lo, hi, series, c);
          } else {
            _drawSeriesInPanel(
                canvas, pgeo, top, lo, hi, series, color);
          }
        });
      }

      // Panel basligi + son deger
      final title = panel.items.map((e) => e.config.label).join(', ');
      _tag(canvas, '$title  ${_panelSummary(panel)}',
          Offset(6, top + 4), c.axisText);

      top += panelHeight + panelGap;
    }
  }

  String _panelSummary(ChartPanel panel) {
    final parts = <String>[];
    for (final ci in panel.items) {
      parts.add(ci.summary((v) => _fmtPanel(v, ci)));
    }
    return parts.join('  ');
  }

  String _fmtPanel(double? v, ComputedIndicator ci) {
    if (v == null) return '—';
    final isOsc = ci.config.pane == IndicatorPane.oscillator;
    return isOsc ? v.toStringAsFixed(2) : _fmt(v);
  }

  double _panelY(double v, double lo, double hi, double h) {
    final range = hi - lo;
    if (!range.isFinite || range == 0) return h / 2;
    return h - ((v - lo) / range).clamp(0.0, 1.0) * h;
  }

  void _drawSeriesInPanel(Canvas canvas, ChartGeometry geo, double top,
      double lo, double hi, List<double?> series, Color color) {
    if (series.length != data.candles.length) return;
    final path = Path();
    var started = false;
    for (var i = geo.first; i < geo.last && i < series.length; i++) {
      final v = series[i];
      if (v == null || !v.isFinite) {
        started = false;
        continue;
      }
      final x = geo.xCenterOf(i);
      final y = top + _panelY(v, lo, hi, panelHeight);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (!started) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _histogramInPanel(Canvas canvas, ChartGeometry geo, double top,
      double lo, double hi, List<double?> series, ChartColors c) {
    if (series.length != data.candles.length) return;
    final p = Paint()..style = PaintingStyle.fill;
    final zero = top + _panelY(0, lo, hi, panelHeight);
    final w = (geo.candleWidth * 0.5).clamp(1.0, 12.0);

    for (var i = geo.first; i < geo.last && i < series.length; i++) {
      final v = series[i];
      if (v == null || !v.isFinite) continue;
      final y = top + _panelY(v, lo, hi, panelHeight);
      p.color =
          v >= 0 ? c.up.withValues(alpha: 0.7) : c.down.withValues(alpha: 0.7);
      final topY = math.min(y, zero);
      final h = (y - zero).abs();
      if (h < 0.4) continue;
      canvas.drawRect(
          Rect.fromLTWH(geo.xCenterOf(i) - w / 2, topY, w, h), p);
    }
  }

  // --------------------------------------------------------------------------
  // Son fiyat / eksenler / capraz imlec
  // --------------------------------------------------------------------------

  void _paintLastPrice(Canvas canvas, ChartGeometry geo, ChartColors c) {
    final last = data.candles.isEmpty
        ? null
        : data.candles[geoSafeLast - 1 < geoSafeFirst ? geoSafeFirst : geoSafeLast - 1];
    if (last == null) return;
    final y = geo.yOfPrice(last.close);
    if (y < 0 || y > geo.plotSize.height) return;

    final color = last.isBullish ? c.up : c.down;
    _stroke(canvas, color, Offset(0, y), Offset(geo.plotSize.width, y), dash: true);
    _tag(canvas, _fmt(last.close),
        Offset(geo.plotSize.width + 4, y - 9), color);
  }

  void _paintPriceAxis(
      Canvas canvas, Size size, ChartGeometry geo, Size plotSize, ChartColors c) {
    final ticks = ChartGeometry.niceTicks(geo.priceMin, geo.priceMax, 5);
    for (final t in ticks) {
      final y = geo.yOfPrice(t);
      if (y < 0 || y > plotSize.height) continue;
      _axisLabel(canvas, _fmt(t), Offset(plotSize.width + 6, y - 7), c);
    }
  }

  void _paintTimeAxis(
      Canvas canvas, Size size, Size plotSize, ChartGeometry geo, ChartColors c) {
    final count = _timeTickCount(geo);
    final step = (geo.count / count).ceil().clamp(1, 1 << 20);

    for (var i = 0; i < geo.count; i += step) {
      final idx = geo.first + i;
      if (idx >= data.candles.length) break;
      final x = geo.xCenterOf(idx);
      final label = _timeLabel(data.candles[idx]);
      if (label.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: c.axisText, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      if (x - tp.width / 2 < 0 || x + tp.width / 2 > plotSize.width) continue;
      tp.paint(canvas, Offset(x - tp.width / 2, plotSize.height + 5));
    }
  }

  String _timeLabel(Candle k) {
    final d = k.date.toLocal();
    final interval = data.viewport.length;
    if (interval > 400) {
      return '${d.day.toString().padLeft(2, '0')}.'
          '${d.month.toString().padLeft(2, '0')}.${d.year % 100}';
    }
    // Intraday mi? Mum araligini tahmin et.
    final span = data.candles.length > 1
        ? (data.candles[1].time - data.candles[0].time)
        : 0;
    if (span <= 0) return '${d.day}.${d.month}';
    final hours = span / Duration.millisecondsPerHour;
    if (hours < 24) {
      return '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}';
  }

  void _axisLabel(Canvas canvas, String text, Offset at, ChartColors c) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: c.axisText, fontSize: 10.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _paintCrosshair(Canvas canvas, Size size, Size plotSize,
      ChartGeometry geo, ChartColors c) {
    final ch = data.crosshair;
    if (ch == null) return;

    final paint = Paint()
      ..color = c.crosshair.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    // Yatay (fiyat)
    final price = data.crosshairPrice;
    if (price != null && price.isFinite) {
      final y = geo.yOfPrice(price);
      if (y >= 0 && y <= plotSize.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        _tag(canvas, _fmt(price), Offset(plotSize.width + 4, y - 9), c.crosshair);
      }
    }

    // Dikey (zaman)
    final idx = data.crosshairIndex;
    if (idx != null) {
      final x = geo.xCenterOf(idx.clamp(0, data.candles.length - 1));
      if (x >= 0 && x <= plotSize.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height - 22), paint);
        final d = idx >= 0 && idx < data.candles.length
            ? data.candles[idx].date.toLocal()
            : null;
        if (d != null) {
          _tag(canvas, _timeFull(d), Offset(x - 44, size.height - 21),
              c.crosshair);
        }
      }
    }
  }

  String _timeFull(DateTime d) {
    final span = data.candles.length > 1
        ? (data.candles[1].time - data.candles[0].time)
        : 0;
    final base = '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
    if (span <= 0 || span > Duration.millisecondsPerDay) return base;
    return '$base ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  }
