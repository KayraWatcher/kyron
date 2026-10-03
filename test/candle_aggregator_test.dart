// GOLD v2 - Faz E: mum birlestirme (aggregation) saf fonksiyonu.
//
// Neden: Yahoo 4 saatlik dilimi sunmuyor (test/interval_probe.dart ile
// dogrulandi: "4 sa" istegi 1 saatlik mum donuyor). Etiketin yaniltici
// olmamasi icin 4 saat, GERCEK 60m mumlardan hesaplaniyor.
//
// Kurallar dogrulanir:
//  * Araya mum EKLENMEZ, bos kova OLUSTURULMAZ (uydurma veri yok).
//  * open = ilk mumunki, close = son mumunki, high/low = en buyuk/kucuk,
//    volume = toplam, time = kova baslangici.
//  * Girdi sirasi korunur; kovalar sirali doner.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/candle/candle_aggregator.dart';
import 'package:gold/domain/entities/candle.dart';

const int _h = 60 * 60 * 1000;
const Duration _bucket = Duration(hours: 4);

Candle _c(int timeMs, {double o = 1, double h = 2, double l = 0.5, double c = 1.5, double? v}) =>
    Candle(
      time: timeMs,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v,
    );

void main() {
  group('aggregateCandles', () {
    test('bos girdi ayni doner', () {
      expect(aggregateCandles(const [], bucket: _bucket), isEmpty);
    });

    test('gecersiz kova girdiyi oldugu gibi birakir', () {
      final src = [_c(0), _c(_h)];
      expect(aggregateCandles(src, bucket: Duration.zero), same(src));
    });

    test('4 saatlik kova: 4 gercek mum 1 bara birlesir', () {
      // Kova baslangici UTC 04:00 (4 * 3600000 tam bolunur).
      const base = 4 * _h;
      final src = [
        _c(base + 0 * _h, o: 10, h: 12, l: 9, c: 11, v: 100),
        _c(base + 1 * _h, o: 11, h: 15, l: 10, c: 14, v: 200),
        _c(base + 2 * _h, o: 14, h: 16, l: 13, c: 13, v: 300),
        _c(base + 3 * _h, o: 13, h: 14, l: 8, c: 9, v: 50),
      ];

      final out = aggregateCandles(src, bucket: _bucket);

      expect(out, hasLength(1));
      final b = out.single;
      expect(b.time, base, reason: 'kova baslangici UTC sinirina yuvarlanmali');
      expect(b.open, 10, reason: 'open ilk mumunki olmali');
      expect(b.high, 16, reason: 'high en buyuk olmali');
      expect(b.low, 8, reason: 'low en kucuk olmali');
      expect(b.close, 9, reason: 'close son mumunki olmali');
      expect(b.volume, 650, reason: 'volume toplam olmali');
    });

    test('kova sinirindan yeni kova baslar', () {
      const base = 4 * _h;
      final src = [
        _c(base, o: 10, h: 12, l: 9, c: 11),
        _c(base + 3 * _h, o: 11, h: 15, l: 10, c: 14),
        _c(base + 4 * _h, o: 20, h: 22, l: 19, c: 21), // yeni kova
      ];

      final out = aggregateCandles(src, bucket: _bucket);

      expect(out, hasLength(2));
      expect(out[0].time, base);
      expect(out[0].open, 10);
      expect(out[0].close, 14);
      expect(out[1].time, base + 4 * _h);
      expect(out[1].open, 20);
      expect(out[1].close, 21);
    });

    test('bostaki kova icin mum URETILMEZ (araya veri eklenmez)', () {
      const base = 4 * _h;
      final src = [
        _c(base, o: 10, h: 12, l: 9, c: 11),
        _c(base + 3 * _h, o: 11, h: 15, l: 10, c: 14),
        // 4+4 = 8 saat BOŞ (kova 3 hic mum almaz)
        _c(base + 12 * _h, o: 20, h: 22, l: 19, c: 21),
      ];

      final out = aggregateCandles(src, bucket: _bucket);

      expect(out, hasLength(2), reason: 'bos kova icin mum eklenmemeli');
      expect(out[0].time, base);
      expect(out[1].time, base + 12 * _h);
    });

    test('volume null ise null kalir; karisik durumda toplanir', () {
      const base = 4 * _h;
      final out = aggregateCandles(
        [
          _c(base, v: null),
          _c(base + _h, v: null),
        ],
        bucket: _bucket,
      );
      expect(out.single.volume, isNull);

      final mixed = aggregateCandles(
        [
          _c(base, v: null),
          _c(base + _h, v: 5),
        ],
        bucket: _bucket,
      );
      expect(mixed.single.volume, 5);
    });

    test('tek mum aynen kova olarak doner', () {
      const base = 4 * _h;
      final out = aggregateCandles([_c(base + _h, o: 7)], bucket: _bucket);
      expect(out, hasLength(1));
      expect(out.single.time, base, reason: 'kova sinirina yuvarlanmali');
      expect(out.single.open, 7);
    });

    test('girdi artan zamanda; cikan kovalar da artan', () {
      final src = <Candle>[
        for (var i = 0; i < 48; i++) _c(i * _h, o: i.toDouble()),
      ];
      final out = aggregateCandles(src, bucket: _bucket);

      expect(out.length, 12); // 48 saat / 4 saat
      for (var i = 1; i < out.length; i++) {
        expect(out[i].time, greaterThan(out[i - 1].time));
      }
      // Hiçbir kova kaybolmadi (48 mum / 4 = 12 kova).
      expect(out.first.open, 0);
      expect(out.last.open, 44);
    });
  });
}
