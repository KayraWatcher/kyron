import '../../domain/entities/candle.dart';

/// Gercek mumlari sabit zaman kovalarinda **birlestirir** (aggregation).
///
/// Neden gerekiyor?
///  * Bazi saglayicilar her dilimi sunmaz. Ornek (dogrulandi:
///    `test/interval_probe.dart`): Yahoo'dan 4 saat istegi **1 saatlik**
///    mum donuyor. Etiket "4 sa" olup veri 1 sa ise bu **yanilticidir**.
///  * Boyle durumlarda istenen dilim, gercek dusuk seviyeli mumlardan
///    **hesaplanir** - ayni yaklasim gram altinin onstan hesaplanmasinda
///    kullanilir.
///
/// ## Kurallar (sahte veri yasagi)
///  * Araya mum **eklenmez**, bosluk **doldurulmaz**. Kova yalnizca
///    kaynaktan gelen mumlari icerir; hic mum yoksa kova olusmaz.
///  * `open` kovadaki **ilk** mumunki, `close` **son** mumunki,
///    `high` en buyuk, `low` en kucuk, `volume` toplamdir.
///  * `time` kovanin **baslangicidir** (kova sinirina yuvarlanir).
///  * Tum degerler kaynaktan gelir; `null` hacim `null` kalir.
///
/// Kovalar [bucket] boyutuna gore UTC bazli yuvarlanir; borsa oturumuna
/// gore hizalanmaz. Bu, 4 saatlik barin gercekten 4 saat anlamina gelmesini
/// saglar.
List<Candle> aggregateCandles(
  List<Candle> src, {
  required Duration bucket,
}) {
  if (src.isEmpty || bucket <= Duration.zero) return src;

  final bucketMs = bucket.inMilliseconds;
  final buckets = <int, Candle>{};
  final order = <int>[];

  for (final c in src) {
    final start = (c.time ~/ bucketMs) * bucketMs;
    final cur = buckets[start];

    if (cur == null) {
      // Kova etiketi her zaman kova BASLANGICIDIR; tek mumlu kovalar da
      // digerleri gibi hizalanir (zaman ekseni tutarli olsun diye).
      buckets[start] = Candle(
        time: start,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
        volume: c.volume,
      );
      order.add(start);
      continue;
    }

    final vol = cur.volume;
    final nextVol = c.volume;
    buckets[start] = Candle(
      time: start,
      open: cur.open,
      high: cur.high > c.high ? cur.high : c.high,
      low: cur.low < c.low ? cur.low : c.low,
      close: c.close, // kovadaki son mumun kapanisi
      volume: (vol == null && nextVol == null)
          ? null
          : (vol ?? 0) + (nextVol ?? 0),
    );
  }

  order.sort();
  return [for (final t in order) buckets[t]!];
}
