// Aşama 17 - Teknik gosterge hesaplari (saf Dart).
//
// Beklentiler elle dogrulanmis bilinen degerlerdir; hicbiri "gibi gorunsun"
// diye yaklasik secilmemistir.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/technical/indicators.dart';

/// Girdi ile ayni uzunlukta olma ve **asla NaN/Infinity** uretme sozlesmesi.
void expectSeriesShape(List<double?> out, int inputLength, String label) {
  expect(out.length, inputLength, reason: '$label uzunlugu girdiyle ayni olmali');
  for (var i = 0; i < out.length; i++) {
    final v = out[i];
    if (v == null) continue;
    expect(v.isFinite, isTrue, reason: '$label[$i] sonucsuz deger: $v');
  }
}

Candle _c(int i, double o, double h, double l, double c, {double? v}) =>
    Candle(
      time: i * 86400000,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v,
    );

/// Buyuyen/dusen karisik bir serisi (tekdüze degil).
List<Candle> _candles(int n) => [
      for (var i = 0; i < n; i++)
        _c(
          i,
          (100 + i).toDouble(),
          (102 + i + (i.isEven ? 1 : 0)).toDouble(),
          (99 + i - (i.isEven ? 0 : 1)).toDouble(),
          (101 + (i.isEven ? 2 : -2) + i).toDouble(),
          v: (1000 + (i % 7) * 100).toDouble(),
        ),
    ];

void main() {
  group('Indicators - hareketli ortalamalar', () {
    test('SMA bilinen degerler', () {
      final out = Indicators.sma(const [1, 2, 3, 4, 5], 3);
      expectSeriesShape(out, 5, 'SMA');
      expect(out[0], isNull);
      expect(out[1], isNull);
      expect(out[2], 2.0);
      expect(out[3], 3.0);
      expect(out[4], 4.0);
    });

    test('SMA periyot <= 0 veya seri kisa ise hicbir deger uretmez', () {
      expect(Indicators.sma(const [1, 2, 3], 0).every((e) => e == null), isTrue);
      expect(Indicators.sma(const [1, 2], 5).every((e) => e == null), isTrue);
      expect(Indicators.sma(const [], 5), isEmpty);
    });

    test('EMA bilinen degerler (k = 0.5)', () {
      final out = Indicators.ema(const [1, 2, 3, 4, 5], 3);
      expectSeriesShape(out, 5, 'EMA');
      expect(out[0], isNull);
      expect(out[2], 2.0);
      expect(out[3], 3.0);
      expect(out[4], 4.0);
    });

    test('EMA tohum (seed) verilirse ilk elemandan itibaren uretir', () {
      final out = Indicators.ema(const [10, 10, 10, 10], 3, seed: 5);
      expect(out.every((e) => e != null), isTrue);
      expect(out[0], closeTo(7.5, 1e-9));
      expect(out[3], closeTo(9.6875, 1e-9));
    });

    test('WMA bilinen degerler (1,2,3 / 3 -> 14/6)', () {
      final out = Indicators.wma(const [1, 2, 3], 3);
      expectSeriesShape(out, 3, 'WMA');
      expect(out[2], closeTo(14 / 6, 1e-9));
    });

    test('SMA her zaman gercek ortalamadan buyuk/kucuk olmali', () {
      final src = [for (var i = 0; i < 40; i++) math.sin(i) * 10 + 50];
      final out = Indicators.sma(src, 10);
      expectSeriesShape(out, src.length, 'SMA');
      final last = out.last!;
      expect(last, greaterThan(0));
      expect(last, lessThan(100));
    });
  });

  group('Indicators - RSI', () {
    test('sadece yukselen seri -> RSI 100', () {
      final src = [for (var i = 1; i <= 20; i++) i.toDouble()];
      final out = Indicators.rsi(src, 14);
      expectSeriesShape(out, 20, 'RSI');
      for (var i = 0; i < 14; i++) {
        expect(out[i], isNull, reason: 'ilk $i eleman hesaplanamamali');
      }
      expect(out[14], 100.0);
      expect(out.last, 100.0);
    });

    test('sadece dusen seri -> RSI 0', () {
      final src = [for (var i = 20; i >= 1; i--) i.toDouble()];
      final out = Indicators.rsi(src, 14);
      expectSeriesShape(out, 20, 'RSI');
      expect(out[14], 0.0);
      expect(out.last, 0.0);
    });

    test('RSI degeri 0 ile 100 arasinda kalmali', () {
      final src = [
        for (var i = 0; i < 60; i++) 100 + math.sin(i / 2) * 10,
      ];
      final out = Indicators.rsi(src, 14);
      expectSeriesShape(out, 60, 'RSI');
      for (final v in out.whereType<double>()) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(100));
      }
    });

    test('seri periyottan kisa ise hicbir deger uretmez', () {
      expect(Indicators.rsi(const [1, 2, 3], 14).every((e) => e == null), isTrue);
    });
  });

  group('Indicators - MACD', () {
    test('uc cizgi de ayni uzunlukta ve adlandirilmis', () {
      final src = [for (var i = 0; i < 60; i++) 100 + i * 0.5];
      final m = Indicators.macd(src);
      expect(m.name, 'MACD');
      expect(m.line('MACD'), isNotNull);
      expect(m.line('Sinyal'), isNotNull);
      expect(m.line('Histogram'), isNotNull);
      for (final line in m.lines.values) {
        expectSeriesShape(line, src.length, 'MACD');
      }
    });

    test('histogram = MACD - sinyal', () {
      final src = [for (var i = 0; i < 60; i++) 100 + i * 0.5];
      final m = Indicators.macd(src);
      final macdLine = m.line('MACD')!;
      final signal = m.line('Sinyal')!;
      final hist = m.line('Histogram')!;
      var checked = 0;
      for (var i = 0; i < src.length; i++) {
        final a = macdLine[i];
        final b = signal[i];
        final h = hist[i];
        if (a == null || b == null || h == null) continue;
        expect(h, closeTo(a - b, 1e-9), reason: 'index $i');
        checked++;
      }
      expect(checked, greaterThan(0), reason: 'eslestirilmis deger yok');
    });

    test('duz artan seride MACD pozitif', () {
      final src = [for (var i = 0; i < 60; i++) (100 + i).toDouble()];
      final m = Indicators.macd(src);
      expect(m.line('MACD')!.last, greaterThan(0));
    });
  });

  group('Indicators - Bollinger', () {
    test('sabit seride ust = orta = alt', () {
      final out = Indicators.bollinger(List<double>.filled(20, 5), period: 20);
      expectSeriesShape(out.line('Üst')!, 20, 'Bollinger üst');
      expectSeriesShape(out.line('Orta')!, 20, 'Bollinger orta');
      expectSeriesShape(out.line('Alt')!, 20, 'Bollinger alt');
      expect(out.line('Üst')!.last, 5.0);
      expect(out.line('Orta')!.last, 5.0);
      expect(out.line('Alt')!.last, 5.0);
    });

    test('degisen seride ust >= orta >= alt', () {
      final src = [for (var i = 0; i < 40; i++) 100 + math.sin(i) * 5];
      final out = Indicators.bollinger(src, period: 20);
      final up = out.line('Üst')!;
      final mid = out.line('Orta')!;
      final low = out.line('Alt')!;
      expectSeriesShape(up, 40, 'Bollinger üst');
      for (var i = 19; i < 40; i++) {
        expect(up[i]!, greaterThanOrEqualTo(mid[i]!));
        expect(low[i]!, lessThanOrEqualTo(mid[i]!));
      }
    });
  });

  group('Indicators - ATR / volatilite', () {
    test('ATR bilinen degerler (Wilder)', () {
      final candles = <Candle>[
        _c(0, 9, 10, 8, 9), // TR = 2
        _c(1, 9, 11, 9, 10), // TR = max(2, |11-9|=2, |9-9|=0) = 2
        // onceki kapanis 10 -> TR = max(13-10=3, |13-10|=3, |10-10|=0) = 3
        _c(2, 10, 13, 10, 11),
      ];

      final a1 = Indicators.atr(candles, 1);
      expectSeriesShape(a1, 3, 'ATR(1)');
      expect(a1[0], 2.0);
      expect(a1[1], 2.0);
      expect(a1.last, 3.0);

      final a3 = Indicators.atr(candles, 3);
      expectSeriesShape(a3, 3, 'ATR(3)');
      expect(a3[2], closeTo(7 / 3, 1e-9));
    });

    test('ATR periyot > seri uzunlugu ise deger uretmez', () {
      expect(Indicators.atr(_candles(5), 50).every((e) => e == null), isTrue);
    });
  });

  group('Indicators - Stokastik / CCI / Williams %R', () {
    test('Stokastik iki cizgi uretir ve 0-100 arasinda kalir', () {
      final candles = _candles(30);
      final st = Indicators.stoch(candles, kPeriod: 14, dPeriod: 3);
      final k = st.line('%K')!;
      final d = st.line('%D')!;
      expectSeriesShape(k, 30, '%K');
      expectSeriesShape(d, 30, '%D');
      for (final v in k.whereType<double>()) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(100));
      }
      expect(k.any((e) => e != null), isTrue);
      expect(d.any((e) => e != null), isTrue);
    });

    test('CCI tekdüze seride 0', () {
      final flat = [
        for (var i = 0; i < 25; i++) _c(i, 100, 100, 100, 100),
      ];
      final out = Indicators.cci(flat, 20);
      expectSeriesShape(out, 25, 'CCI');
      expect(out.last, 0.0);
    });

    test('Williams %R tekdüze seride -50, aralikta [-100, 0]', () {
      final flat = [
        for (var i = 0; i < 25; i++) _c(i, 100, 100, 100, 100),
      ];
      expect(Indicators.williamsR(flat, 14).last, -50.0);

      final moving = _candles(30);
      final out = Indicators.williamsR(moving, 14);
      expectSeriesShape(out, 30, 'Williams %R');
      for (final v in out.whereType<double>()) {
        expect(v, greaterThanOrEqualTo(-100));
        expect(v, lessThanOrEqualTo(0));
      }
    });
  });

  group('Indicators - hacim', () {
    test('VWAP bilinen degerler', () {
      final candles = <Candle>[
        _c(0, 10, 10, 10, 10, v: 100.0),
        _c(1, 20, 20, 20, 20, v: 100.0),
      ];
      final out = Indicators.vwap(candles);
      expectSeriesShape(out, 2, 'VWAP');
      expect(out[0], 10.0);
      expect(out[1], 15.0);
    });

    test('hacmi olmayan mum VWAP\'i degistirmez', () {
      final candles = <Candle>[
        _c(0, 10, 10, 10, 10, v: 100.0),
        _c(1, 20, 20, 20, 20), // volume yok
      ];
      final out = Indicators.vwap(candles);
      expect(out[1], 10.0);
    });

    test('OBV bilinen degerler', () {
      final candles = <Candle>[
        _c(0, 10, 10, 10, 10, v: 100.0),
        _c(1, 10, 11, 10, 11, v: 50.0), // yukselis
        _c(2, 11, 12, 11, 12, v: 30.0), // yukselis
        _c(3, 12, 12, 11, 11, v: 20.0), // dusus
      ];
      final out = Indicators.obv(candles);
      expectSeriesShape(out, 4, 'OBV');
      expect(out[0], 0.0);
      expect(out[1], 50.0);
      expect(out[2], 80.0);
      expect(out[3], 60.0);
    });

    test('volume serisi null hacimleri oldugu gibi tasir', () {
      final candles = <Candle>[
        _c(0, 10, 10, 10, 10, v: 100.0),
        _c(1, 10, 10, 10, 10),
      ];
      final out = Indicators.volume(candles);
      expect(out, [100.0, null]);
    });
  });

  group('Indicators - sozlesme: uzunluk ve sonlu deger', () {
    test('tum gostergeler girdi uzunlugunu korur ve NaN uretmez', () {
      final candles = _candles(80);
      final closes = [for (final c in candles) c.close];

      final cases = <String, List<double?>>{
        'SMA': Indicators.sma(closes, 20),
        'EMA': Indicators.ema(closes, 20),
        'WMA': Indicators.wma(closes, 20),
        'RSI': Indicators.rsi(closes, 14),
        'CCI': Indicators.cci(candles, 20),
        'Williams %R': Indicators.williamsR(candles, 14),
        'ATR': Indicators.atr(candles, 14),
        'OBV': Indicators.obv(candles),
        'VWAP': Indicators.vwap(candles),
        'Volume': Indicators.volume(candles),
      };
      cases.forEach((name, out) => expectSeriesShape(out, 80, name));

      final multi = <String, Map<String, List<double?>>>{
        'MACD': Indicators.macd(closes).lines,
        'Bollinger': Indicators.bollinger(closes, period: 20).lines,
        'Stokastik': Indicators.stoch(candles, kPeriod: 14).lines,
      };
      multi.forEach((name, lines) {
        lines.forEach((key, out) => expectSeriesShape(out, 80, '$name/$key'));
      });
    });

    test('IndicatorSeries.last null degerleri atlatarak son doluyu bulur', () {
      const s = IndicatorSeries(name: 'x', values: [null, 1.0, null, 2.0, null]);
      expect(s.last, 2.0);
      expect(s.length, 5);

      const empty = IndicatorSeries(name: 'y', values: [null, null]);
      expect(empty.last, isNull);
    });
  });
}
