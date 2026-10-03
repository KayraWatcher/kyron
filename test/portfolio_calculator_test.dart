// Aşama 17 - Portfoy hesaplari (kâr/zarar, %, dagilim).
//
// Kurallar:
//  * Fiyati alinamayan kalem hesaba **girmez** ve `hasMissingPrices` set edilir.
//  * `null` / `NaN` fiyatla hicbir sonuc uretilmez.
//  * Komisyon maliyete dahildir.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/portfolio.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/portfolio/portfolio_calculator.dart';

Quote _q(
  String id, {
  double? price,
  double? previousClose,
  double? changePercent,
  double? bid,
  double? ask,
}) =>
    Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 2, 12, 0),
      price: price,
      previousClose: previousClose,
      changePercent: changePercent,
      bid: bid,
      ask: ask,
    );

PortfolioTransaction _buy({
  required String id,
  required String asset,
  required double qty,
  required double price,
  double fee = 0,
  DateTime? date,
}) =>
    PortfolioTransaction(
      id: id,
      assetId: asset,
      quantity: qty,
      price: price,
      date: date ?? DateTime(2026, 1, 1),
      fee: fee,
    );

PortfolioTransaction _sell({
  required String id,
  required String asset,
  required double qty,
  required double price,
  double fee = 0,
  DateTime? date,
}) =>
    PortfolioTransaction(
      id: id,
      assetId: asset,
      quantity: qty,
      price: price,
      date: date ?? DateTime(2026, 2, 1),
      fee: fee,
      isSell: true,
    );

void main() {
  group('PortfolioCalculator - temel kâr/zarar', () {
    test('alis: deger, maliyet, kâr ve %', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'gram-altin', qty: 10, price: 100, fee: 5),
        ],
        names: const {'gram-altin': 'Gram Altın'},
        quotes: {'gram-altin': _q('gram-altin', price: 110)},
      );

      expect(s.items, hasLength(1));
      final item = s.items.single;

      // Maliyet = nominal + komisyon = 10*100 + 5
      expect(item.totalCost, 1005);
      expect(item.totalQuantity, 10);
      expect(item.avgCost, closeTo(100.5, 1e-9));

      // Deger = 10 * 110
      expect(item.currentValue, 1100);
      expect(item.currentPrice, 110);

      // Kâr = 1100 - 1005 = 95
      expect(item.profitLoss, 95);
      expect(item.profitLossPercent, closeTo(95 / 1005 * 100, 1e-9));

      expect(s.totalValue, 1100);
      expect(s.totalCost, 1005);
      expect(s.profitLoss, 95);
      expect(s.hasMissingPrices, isFalse);

      expect(item.assetName, 'Gram Altın');
    });

    test('komisyonsuz alista maliyet yalnizca nominaldir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 2, price: 50),
        ],
        quotes: {'x': _q('x', price: 50)},
      );
      expect(s.totalCost, 100);
      expect(s.profitLoss, 0);
      expect(s.profitLossPercent, 0);
    });

    test('kismi satis: maliyet orantili dusulur, satis komisyonu eklenir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(
            id: 't1',
            asset: 'x',
            qty: 10,
            price: 100,
            date: DateTime(2026, 1, 1),
          ),
          _sell(
            id: 't2',
            asset: 'x',
            qty: 5,
            price: 120,
            fee: 10,
            date: DateTime(2026, 2, 1),
          ),
        ],
        quotes: {'x': _q('x', price: 110)},
      );

      final item = s.items.single;
      expect(item.totalQuantity, 5);
      // Kalan: 5 adet * 100 maliyet + 10 satis komisyonu = 510
      expect(item.totalCost, 510);
      expect(item.avgCost, 102);
      expect(item.currentValue, 550);
      expect(item.profitLoss, 40);
      expect(item.profitLossPercent, closeTo(40 / 510 * 100, 1e-9));
    });

    test('tamamini satisa gecirilen pozisyonda yalnizca komisyon zarari kalinir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 10, price: 100),
          _sell(id: 't2', asset: 'x', qty: 10, price: 100, fee: 5),
        ],
        quotes: {'x': _q('x', price: 110)},
      );

      final item = s.items.single;
      expect(item.totalQuantity, 0);
      expect(item.totalCost, 5); // satis komisyonu
      expect(item.currentValue, 0);
      expect(item.profitLoss, -5);
      expect(item.profitLossPercent, -100);
      expect(s.totalValue, 0);
      expect(s.totalCost, 5);
      expect(s.profitLoss, -5);
    });
  });

  group('PortfolioCalculator - gunluk degisim', () {
    test('onceki kapanisa gore gunlük kâr', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 10, price: 100),
        ],
        quotes: {'x': _q('x', price: 110, previousClose: 105)},
      );

      // % degisim = (110-105)/105 = %4,7619
      const expectedPct = (110 - 105) / 105 * 100;
      expect(s.dayChangePercent, closeTo(expectedPct, 1e-9));

      // Onceki toplam 1050 -> gunluk artis 50
      expect(s.dayChange, closeTo(50, 1e-6));
      expect(s.dayChange.isFinite, isTrue);
    });

    test('changePercent dogrudan verilmis onceliklidir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 1, price: 100),
        ],
        quotes: {'x': _q('x', price: 100, changePercent: 2.5)},
      );
      expect(s.dayChangePercent, closeTo(2.5, 1e-9));
    });

    test('onceki kapanis yoksa gunlük degisim uydurulmaz', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 1, price: 100),
        ],
        quotes: {'x': _q('x', price: 100)},
      );
      expect(s.dayChange, 0);
      expect(s.dayChangePercent, 0);
      expect(s.dayChange.isFinite, isTrue);
    });

    test('% -100 (bolme sifir) NaN uretmez, diger kalemleri zehirlemez', () {
      // Eski hata: onceki deger = guncel / (1 + (-100)/100) -> bolme sifir
      // -> Infinity/NaN `dayChange`'e karisiyordu ("NaN TL" gorunuyordu).
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'x', qty: 10, price: 100),
          _buy(id: 't2', asset: 'y', qty: 5, price: 10),
        ],
        quotes: {
          'x': _q('x', price: 100, changePercent: -100),
          'y': _q('y', price: 12, previousClose: 10),
        },
      );

      expect(s.dayChange.isFinite, isTrue, reason: 'NaN asla gecmez');
      expect(s.dayChangePercent.isFinite, isTrue);
      // y kalemi: deger 60, onceki 50 -> +10 (x katkisi bilinmiyor: atlandi)
      expect(s.dayChange, closeTo(10, 1e-6));
      // Onceki toplam = 1060 - 10 = 1050
      expect(s.dayChangePercent, closeTo(10 / 1050 * 100, 1e-6));
    });
  });

  group('PortfolioCalculator - fiyat yoksa uydurma deger uretilmez', () {
    test('fiyati olmayan kalem toplamlara girmez, isaretlenir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'a', qty: 10, price: 100), // fiyat yok
          _buy(id: 't2', asset: 'b', qty: 5, price: 50), // fiyat var
        ],
        quotes: {'b': _q('b', price: 60)},
      );

      expect(s.hasMissingPrices, isTrue);
      expect(s.items, hasLength(2));

      final missing = s.items.firstWhere((i) => i.assetId == 'a');
      expect(missing.hasPrice, isFalse);
      expect(missing.currentPrice, isNull);
      expect(missing.currentValue, 0);

      // Toplamlar yalnizca fiyati bilinen kalemi kapsar; boylece
      // profitLoss yaniltici olmaz.
      expect(s.totalValue, 300); // 5 * 60
      expect(s.totalCost, 250); // 5 * 50
      expect(s.profitLoss, 50);
      expect(s.profitLossPercent, closeTo(50 / 250 * 100, 1e-9));
      expect(s.profitLoss.isFinite, isTrue);
    });

    test('hicbir fiyat yoksa tum toplamlar sifir ve sonlu kalir', () {
      final s = PortfolioCalculator.compute(
        transactions: [_buy(id: 't1', asset: 'a', qty: 10, price: 100)],
        quotes: const {},
      );

      expect(s.hasMissingPrices, isTrue);
      expect(s.totalValue, 0);
      expect(s.totalCost, 0);
      expect(s.profitLoss, 0);
      expect(s.profitLossPercent, 0);
      expect(s.dayChange, 0);
      expect(s.dayChangePercent, 0);
      for (final v in [s.totalValue, s.profitLoss, s.profitLossPercent]) {
        expect(v.isFinite, isTrue);
      }
    });

    test('NaN fiyatli quote hesaba girmez', () {
      final s = PortfolioCalculator.compute(
        transactions: [_buy(id: 't1', asset: 'a', qty: 10, price: 100)],
        quotes: {'a': _q('a', price: double.nan)},
      );
      expect(s.hasMissingPrices, isTrue);
      expect(s.totalValue, 0);
      expect(s.profitLoss.isFinite, isTrue);
      expect(s.profitLossPercent.isFinite, isTrue);
    });
  });

  group('PortfolioCalculator - gecersiz islemler', () {
    test('miktar <= 0 veya fiyat < 0 veya komisyon < 0 yok sayilir', () {
      expect(
        PortfolioTransaction(
          id: 'x',
          assetId: 'a',
          quantity: 0,
          price: 10,
          date: DateTime(2026),
        ).isValid,
        isFalse,
      );
      expect(
        PortfolioTransaction(
          id: 'x',
          assetId: 'a',
          quantity: 1,
          price: -1,
          date: DateTime(2026),
        ).isValid,
        isFalse,
      );
      expect(
        PortfolioTransaction(
          id: 'x',
          assetId: 'a',
          quantity: 1,
          price: 1,
          fee: -1,
          date: DateTime(2026),
        ).isValid,
        isFalse,
      );
      expect(
        PortfolioTransaction(
          id: 'x',
          assetId: 'a',
          quantity: 1,
          price: double.nan,
          date: DateTime(2026),
        ).isValid,
        isFalse,
      );

      final s = PortfolioCalculator.compute(
        transactions: [
          PortfolioTransaction(
            id: 'bad1',
            assetId: 'a',
            quantity: 0,
            price: 10,
            date: DateTime(2026),
          ),
          PortfolioTransaction(
            id: 'bad2',
            assetId: 'a',
            quantity: 5,
            price: -10,
            date: DateTime(2026),
          ),
        ],
      );
      expect(s.isEmpty, isTrue);
      expect(s, PortfolioSummary.empty);
    });

    test('bos liste bos ozet dondurur', () {
      expect(PortfolioCalculator.compute(transactions: const []), PortfolioSummary.empty);
    });
  });

  group('PortfolioCalculator - dagilim', () {
    test('paylar toplami %100 olur', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'a', qty: 3, price: 100),
          _buy(id: 't2', asset: 'b', qty: 1, price: 100),
        ],
        quotes: {
          'a': _q('a', price: 100), // 300
          'b': _q('b', price: 100), // 100
        },
      );

      expect(s.totalValue, 400);

      final alloc = PortfolioCalculator.allocation(s);
      expect(alloc, hasLength(2));
      // Buyukten kucuge siralidir.
      expect(alloc.first.assetId, 'a');
      expect(alloc.first.share, closeTo(75, 1e-9));
      expect(alloc.last.share, closeTo(25, 1e-9));

      final sum = alloc.fold<double>(0, (acc, e) => acc + e.share);
      expect(sum, closeTo(100, 1e-9));
    });

    test('toplam deger sifirda bos dagilim doner', () {
      final s = PortfolioCalculator.compute(transactions: const []);
      expect(PortfolioCalculator.allocation(s), isEmpty);
    });

    test('shareOf sifir/butunsel toplamda sifir doner', () {
      const item = PortfolioItem(
        assetId: 'a',
        assetName: 'A',
        totalQuantity: 1,
        avgCost: 1,
        totalCost: 1,
        currentValue: 10,
        profitLoss: 0,
        profitLossPercent: 0,
      );
      expect(item.shareOf(0), 0);
      expect(item.shareOf(-5), 0);
      expect(item.shareOf(double.nan), 0);
      expect(item.shareOf(20), closeTo(50, 1e-9));
    });
  });

  group('PortfolioCalculator - siralama', () {
    test('kalemler deger azalan sirada gelir', () {
      final s = PortfolioCalculator.compute(
        transactions: [
          _buy(id: 't1', asset: 'small', qty: 1, price: 10),
          _buy(id: 't2', asset: 'big', qty: 10, price: 100),
        ],
        quotes: {
          'small': _q('small', price: 10),
          'big': _q('big', price: 100),
        },
      );
      expect(s.items.first.assetId, 'big');
      expect(s.items.last.assetId, 'small');
    });
  });
}
