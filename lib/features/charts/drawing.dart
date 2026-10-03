import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_types.dart';

/// Cizim aracinin tuttugu veri noktalari.
///
/// Noktalar **mum dizini + fiyat** ciftindedir; ekran pikseline cevrilirken
/// boylece zoom/pan'de cizim mumlere kilitli kalir.
class DrawingPoint {
  const DrawingPoint(this.index, this.price);

  final int index;
  final double price;

  DrawingPoint shift(int dIndex, double dPrice) =>
      DrawingPoint(index + dIndex, price + dPrice);
}

/// Grafik uzerine cizilen nesne.
class Drawing {
  const Drawing({
    required this.id,
    required this.type,
    required this.points,
    this.label,
  });

  final String id;
  final DrawingTool type;

  /// 1, 2 veya 3 nokta (kanal/extension icin ucuncu).
  final List<DrawingPoint> points;

  final String? label;

  Drawing move(int dIndex, double dPrice) => Drawing(
        id: id,
        type: type,
        label: label,
        points: [
          for (final p in points) p.shift(dIndex, dPrice),
        ],
      );

  Drawing copyWithPoints(List<DrawingPoint> p) => Drawing(
        id: id,
        type: type,
        label: label,
        points: p,
      );
}

/// Fibonacci duzeyleri (Retracement).
/// Kural: 0 / 0.236 / 0.382 / 0.5 / 0.618 / 0.786 / 1
const List<double> kFibRetracementLevels = [0, .236, .382, .5, .618, .786, 1];

/// Fibonacci Extension duzeyleri.
const List<double> kFibExtensionLevels = [0, .618, 1, 1.618, 2.618];

/// Retracement icin fiyat duzeyleri.
List<double> fibRetracementPrices(Drawing d) {
  if (d.points.length < 2) return const [];
  final a = d.points.first.price;
  final b = d.points[1].price;
  final delta = b - a;
  return [for (final f in kFibRetracementLevels) a + delta * f];
}

/// Extension icin fiyat duzeyleri (A, B, C uc nokta).
///
/// AB dalgasinin uzantisi C noktasindan olculur:
/// `seviye = C + (B - A) * f`.  Boylece 0.618 / 1 / 1.618 / 2.618
/// klasik uzantilari elde edilir.
List<double> fibExtensionPrices(Drawing d) {
  if (d.points.length < 3) return const [];
  final a = d.points[0].price;
  final b = d.points[1].price;
  final c = d.points[2].price;
  final ab = b - a;
  if (!ab.isFinite || !c.isFinite) return const [];
  return [
    for (final f in kFibExtensionLevels)
      if ((c + ab * f).isFinite) c + ab * f,
  ];
}

/// Bir cizimin ekran uzerindeki tahmini "agirlik merkezi" - secim/hit test
/// icin kullanilir.
Offset drawingCenter(List<DrawingPoint> pts) {
  if (pts.isEmpty) return Offset.zero;
  double x = 0;
  double y = 0;
  for (final p in pts) {
    x += p.index.toDouble();
    y += p.price;
  }
  return Offset(x / pts.length, y / pts.length);
}

/// Cizim araci icin gerekli minimum nokta sayisi.
int requiredPointsFor(DrawingTool tool) => switch (tool) {
      DrawingTool.hLine ||
      DrawingTool.vLine ||
      DrawingTool.supportResistance =>
        1,
      DrawingTool.trendLine ||
      DrawingTool.measure ||
      DrawingTool.fibRetracement =>
        2,
      DrawingTool.channel || DrawingTool.fibExtension => 3,
      DrawingTool.none => 0,
    };

/// Iki nokta arasindaki olcu sonucu.
class MeasureResult {
  const MeasureResult({
    required this.priceDiff,
    required this.percent,
    required this.bars,
    required this.startPrice,
    required this.endPrice,
  });

  final double priceDiff;
  final double percent;
  final int bars;
  final double startPrice;
  final double endPrice;

  static MeasureResult? of(Drawing d) {
    if (d.points.length < 2) return null;
    final a = d.points.first;
    final b = d.points[1];
    final diff = b.price - a.price;
    final pct = a.price == 0 ? null : diff / a.price * 100;
    if (!diff.isFinite || pct == null || !pct.isFinite) return null;
    return MeasureResult(
      priceDiff: diff,
      percent: pct,
      bars: (b.index - a.index).abs(),
      startPrice: a.price,
      endPrice: b.price,
    );
  }
}

/// Destek/direnc cizgilerini verilen fiyat listesinden olusturur.
List<Drawing> buildSupportResistance({
  required String idPrefix,
  required List<double> levels,
  required int firstIndex,
  required int lastIndex,
  required String label,
}) {
  final out = <Drawing>[];
  var i = 0;
  for (final p in levels) {
    if (!p.isFinite) continue;
    out.add(Drawing(
      id: '${idPrefix}_$i',
      type: DrawingTool.supportResistance,
      label: label,
      points: [
        DrawingPoint(firstIndex, p),
        DrawingPoint(lastIndex, p),
      ],
    ));
    i++;
  }
  return out;
}

/// Paralel kanal icin uc noktadan olusturucu.
Drawing buildChannel({
  required String id,
  required DrawingPoint a,
  required DrawingPoint b,
  required DrawingPoint offset,
}) {
  return Drawing(
    id: id,
    type: DrawingTool.channel,
    points: [a, b, offset],
  );
}

/// Rastgele/uretilmis deger icermez; yalnizca geometrik mesafe.
double distance(DrawingPoint a, DrawingPoint b) {
  return math.sqrt(math.pow(a.index - b.index, 2).toDouble() +
      math.pow(a.price - b.price, 2).toDouble());
}
