import 'dart:math' as math;

import '../../domain/entities/candle.dart';

/// Heikin Ashi mum donusumleri.
///
/// Kaynak seriyi **degistirmez**; yeni bir seri uretir. Boylece kullanici
/// Mum <-> Heikin Ashi gecisinde gercek veriyi kaybetmez.
///
/// **Dizin hizasi garanti altindadir:** donusen listenin uzunlugu ve her
/// elemaninin `time` degeri kaynakla birebir aynidir. Boylece imlec indeksi,
/// gosterge serileri ve OHLC bicimlendirmesi Heikin Ashi modunda da kaymaz.
/// Donusum uretilemeyen (bozuk/eksik) bir kayit **oldugu gibi korunur**;
/// uydurma mum uretilmez.
abstract final class HeikinAshi {
  static List<Candle> convert(List<Candle> source) {
    if (source.isEmpty) return const [];

    final out = <Candle>[];
    double? prevClose;
    double prevOpen = source.first.open.isFinite ? source.first.open : 0;

    for (var i = 0; i < source.length; i++) {
      final c = source[i];

      final close = (c.open + c.high + c.low + c.close) / 4;
      final open = i == 0
          ? (c.open + c.close) / 2
          : (prevOpen + (prevClose ?? c.open)) / 2;
      final high = math.max(c.high, math.max(open, close));
      final low = math.min(c.low, math.min(open, close));

      if (open.isFinite &&
          close.isFinite &&
          high.isFinite &&
          low.isFinite) {
        out.add(Candle(
          time: c.time,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: c.volume,
        ));
        prevOpen = open;
        prevClose = close;
        continue;
      }

      // Donusum anlamsiz (bozuk/eksik kayit): gercek mum aynen alinir.
      // Hem sahte veri uretilmez hem de sonraki mumlarin hizasi kaymaz.
      out.add(c);
      prevOpen = c.open.isFinite ? c.open : prevOpen;
      prevClose = c.close.isFinite ? c.close : prevClose;
    }
    return out;
  }
}
