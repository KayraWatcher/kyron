// Aşama 17 - Hesaplanan (turev) deger matematigi.
//
// Kutuphane degil; yalnizca saf matematik + varlik carpimlari.
// "Hesaplanan" ve "dogrudan piyasa" degerleri burada ayristirilir.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/domain/entities/quote.dart';

void main() {
  group('MetalMath - ons -> gram', () {
    test('1 troy ons = 31,1034768 gram', () {
      expect(MetalMath.gramsPerOunce, 31.1034768);
    });

    test('bilinen ornek: 4000 USD ons + 50 TL kur', () {
      final g = MetalMath.gramFromOunce(4000, 50);
      expect(g, isNotNull);
      // 4000 * 50 / 31.1034768
      expect(g!, closeTo(6430.15, 0.01));
    });

    test('bilinen ornek: 2650 USD ons + 41,5 TL kur', () {
      final g = MetalMath.gramFromOunce(2650, 41.5);
      expect(g, closeTo(3535.78, 0.01));
    });

    test('kur veya ons gecersizse null (uydurma yok)', () {
      expect(MetalMath.gramFromOunce(double.nan, 50), isNull);
      expect(MetalMath.gramFromOunce(4000, double.nan), isNull);
      expect(MetalMath.gramFromOunce(double.infinity, 50), isNull);
      expect(MetalMath.gramFromOunce(-4000, 50), isNull);
      expect(MetalMath.gramFromOunce(4000, -50), isNull);
      expect(MetalMath.gramFromOunce(0, 50), isNull);
    });

    test('kur arttikca gram fiyati artar', () {
      final low = MetalMath.gramFromOunce(3000, 40)!;
      final high = MetalMath.gramFromOunce(3000, 45)!;
      expect(high, greaterThan(low));
    });
  });

  group('MetalMath.combinePercents - iki bileşenli getiri', () {
    test('ikisi de %10 -> kabaca %21 (carpan degil, getiri birlesimi)', () {
      final v = MetalMath.combinePercents(10, 10);
      expect(v, isNotNull);
      expect(v!, closeTo(21, 1e-9));
    });

    test('matematiksel tanim: ((1+a)(1+b)-1)*100', () {
      const a = 3.7;
      const b = -1.25;
      const expected = ((1 + a / 100) * (1 + b / 100) - 1) * 100;
      expect(MetalMath.combinePercents(a, b), closeTo(expected, 1e-12));
    });

    test('esik degil getiri: %50 + %50 -> %125', () {
      expect(MetalMath.combinePercents(50, 50), closeTo(125, 1e-9));
    });

    test('biri yoksa digeri oldugu gibi gecer', () {
      expect(MetalMath.combinePercents(null, 5), 5);
      expect(MetalMath.combinePercents(5, null), 5);
      expect(MetalMath.combinePercents(0, null), 0);
    });

    test('ikisi de yoksa null (uydurma yok)', () {
      expect(MetalMath.combinePercents(null, null), isNull);
    });

    test('NaN / Infinity girdi yok sayilir', () {
      expect(MetalMath.combinePercents(double.nan, 5), 5);
      expect(MetalMath.combinePercents(5, double.nan), 5);
      expect(MetalMath.combinePercents(double.nan, double.nan), isNull);
      // Sonsuz getiri gecersizdir; diger bileşen oldugu gibi gecer.
      expect(MetalMath.combinePercents(double.infinity, 5), 5);
      expect(MetalMath.combinePercents(double.nan, double.infinity), isNull);
    });

    test('sifir getiri sifirci getirir', () {
      expect(MetalMath.combinePercents(0, 0), 0);
    });

    test('sonuc her zaman sonlu', () {
      const samples = <double?>[
        100,
        -100,
        -50,
        0,
        1e6,
        -1e6,
        null,
        double.nan,
      ];
      for (final a in samples) {
        for (final b in samples) {
          final v = MetalMath.combinePercents(a, b);
          if (v != null) {
            expect(v.isFinite, isTrue, reason: '($a, $b) -> $v');
          }
        }
      }
    });
  });

  group('GoldWeights - darphane/ayar carpanlari', () {
    test('gram karsiliklari', () {
      expect(GoldWeights.ceyrek, 1.75);
      expect(GoldWeights.yarim, 3.50);
      expect(GoldWeights.tam, 7.00);
      expect(GoldWeights.cumhuriyet, 7.216);
      expect(GoldWeights.ata, 7.216);
      expect(GoldWeights.bilezik22, 0.916);
    });

    test('agirlik mantigi tutarli: yarim = 2 * ceyrek, tam = 4 * ceyrek', () {
      expect(GoldWeights.yarim, closeTo(GoldWeights.ceyrek * 2, 1e-9));
      expect(GoldWeights.tam, closeTo(GoldWeights.ceyrek * 4, 1e-9));
    });

    test('saflik carpani 1\'den kucuk', () {
      expect(GoldWeights.bilezik22, lessThan(1));
      expect(GoldWeights.bilezik22, greaterThan(0));
    });
  });

  group('Quote - turev hesaplar (dogrudan ve hesaplanan kaynak)', () {
    Quote sample({
      double? price,
      double? bid,
      double? ask,
      double? change,
      double? changePercent,
      double? previousClose,
    }) =>
        Quote(
          assetId: 'x',
          source: QuoteSourceLabel.calculated,
          updatedAt: DateTime(2026, 10, 2),
          price: price,
          bid: bid,
          ask: ask,
          change: change,
          changePercent: changePercent,
          previousClose: previousClose,
        );

    test('makas = satis - alis', () {
      final q = sample(price: 100, bid: 99.8, ask: 100.2);
      expect(q.spread, closeTo(0.4, 1e-9));
      expect(q.spreadPercent, closeTo(0.4 / 100.2 * 100, 1e-9));
    });

    test('makas verisi yoksa null (uydurma 0 yok)', () {
      expect(sample(price: 100).spread, isNull);
      expect(sample(bid: 10).spread, isNull);
    });

    test('degisim yoksa onceki kapanistan hesaplanir', () {
      final q = sample(price: 110, previousClose: 100);
      expect(q.effectiveChange, closeTo(10, 1e-9));
      expect(q.effectiveChangePercent, closeTo(10, 1e-9));
    });

    test('acik degisim degeri varsa onceliklidir', () {
      final q = sample(
        price: 110,
        previousClose: 100,
        change: 7,
        changePercent: 3,
      );
      expect(q.effectiveChange, 7);
      expect(q.effectiveChangePercent, 3);
    });

    test('onceki kapanis sifir/yok ise yuzde null', () {
      expect(sample(price: 10, previousClose: 0).effectiveChangePercent, isNull);
      expect(sample(price: 10).effectiveChangePercent, isNull);
      expect(sample(price: 10).effectiveChange, isNull);
    });

    test('hasPrice yalnizca sonlu ve mevcut fiyat icin true', () {
      expect(sample(price: 10).hasPrice, isTrue);
      expect(sample(price: 0).hasPrice, isTrue);
      expect(sample().hasPrice, isFalse);
      expect(sample(price: double.nan).hasPrice, isFalse);
      expect(sample(price: double.infinity).hasPrice, isFalse);
    });

    test('kaynak etiketi "Hesaplanan" olarak ayristirilir', () {
      expect(
        QuoteSourceLabel.calculated.label,
        'Hesaplanan',
      );
      expect(QuoteSourceLabel.market.label, 'Piyasa');
      expect(QuoteSourceLabel.unavailable.isUnavailable, isTrue);
    });

    test('veri yok etiketi olusturucu uygun alanlari sifirlar', () {
      final q = Quote.unavailableFor('usd-try');
      expect(q.assetId, 'usd-try');
      expect(q.source, QuoteSourceLabel.unavailable);
      expect(q.hasPrice, isFalse);
      expect(q.spread, isNull);
      expect(q.effectiveChangePercent, isNull);
    });
  });
}
