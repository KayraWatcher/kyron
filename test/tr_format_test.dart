// Aşama 17 - Turkce sayi/tarih bicimlendirme testleri.
//
// Kural: `null`, `NaN` ve `Infinity` asla ekrana yazdirilmaz; yerine
// `TrFormat.noData` ("—") doner.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/format/tr_format.dart';

void main() {
  group('TrFormat.para / fiyat', () {
    test('6024,5 -> "6.024,50"', () {
      expect(TrFormat.money(6024.5), '6.024,50');
    });

    test('para birimi eki ile "6.024,50 TL"', () {
      expect(TrFormat.moneyWithCurrency(6024.5, 'TL'), '6.024,50 TL');
    });

    test('buyuk fiyat binlik ayrac ile "50.000,00"', () {
      expect(TrFormat.price(50000), '50.000,00');
    });

    test('orta fiyat iki ondalik "49,14"', () {
      expect(TrFormat.price(49.1416), '49,14');
    });

    test('cok kucuk fiyat dort ondalik "0,0001"', () {
      expect(TrFormat.price(0.0001234), '0,0001');
    });

    test('sifir para degeri "0,00" olarak gosterilir', () {
      // Para bicimi (kâr/zarar gibi) sifir gecerli bir degerdir.
      expect(TrFormat.money(0), '0,00');
    });

    test('istenen ondalik sayisi sessizce 2\'ye dusurulmez', () {
      // Eski hata: yalnizca 0/2/4 elden geciyordu (3 -> 2 basamak).
      expect(TrFormat.money(42.1234, decimals: 3), '42,123');
      expect(TrFormat.money(42.1235, decimals: 1), '42,1');
      expect(TrFormat.money(6024.4, decimals: 0), '6.024');
    });

    test('dort ondalik artik binlik ayirici ile yazilir', () {
      // Eski hata: decimals=4 -> `_plain4` ("1234,5678").
      expect(TrFormat.money(1234.5678, decimals: 4), '1.234,5678');
      expect(TrFormat.money(0.123456, decimals: 6), '0,123456');
    });
  });

  group('TrFormat.parse - Turkce giris ayristirma', () {
    test('"1.5" -> 1.5 (ESKI HATA: 15 oluyordu)', () {
      expect(TrFormat.parse('1.5'), 1.5);
      expect(TrFormat.parse('12.5'), 12.5);
    });

    test('binlik nokta 3 hane ise korunur', () {
      expect(TrFormat.parse('1.500'), 1500);
      expect(TrFormat.parse('1.234.567'), 1234567);
      expect(TrFormat.parse('10.500'), 10500);
    });

    test('on sifir varsa nokta ondaliktir', () {
      expect(TrFormat.parse('0.500'), 0.5);
      expect(TrFormat.parse('0.25'), 0.25);
    });

    test('virgul ondaliktir (Turkce kural)', () {
      expect(TrFormat.parse('1,5'), 1.5);
      expect(TrFormat.parse('3.500,50'), 3500.50);
      expect(TrFormat.parse('3500,50'), 3500.50);
    });

    test('iki ayirici de varsa son ayirici ondaliktir', () {
      expect(TrFormat.parse('1,500.25'), 1500.25);
      expect(TrFormat.parse('1.500,25'), 1500.25);
    });

    test('isaret ve bosluk kabul edilir', () {
      expect(TrFormat.parse('-2,5'), -2.5);
      expect(TrFormat.parse('+2,5'), 2.5);
      expect(TrFormat.parse('  6.024,50  '), 6024.50);
      expect(TrFormat.parse('.5'), 0.5);
    });

    test('gecersiz giris -> null (uydurma deger yok)', () {
      expect(TrFormat.parse(''), isNull);
      expect(TrFormat.parse('   '), isNull);
      expect(TrFormat.parse('abc'), isNull);
      expect(TrFormat.parse('12abc'), isNull);
      expect(TrFormat.parse('1,2,3.4.5x'), isNull);
      expect(TrFormat.parse('-'), isNull);
    });
  });

  group('TrFormat.yuzde / degisim', () {
    test('1.42 -> "%+1,42"', () {
      expect(TrFormat.percent(1.42), '%+1,42');
    });

    test('-1.42 -> "%-1,42"', () {
      expect(TrFormat.percent(-1.42), '%-1,42');
    });

    test('imzali degisim 1.42 -> "+1,42"', () {
      expect(TrFormat.signed(1.42), '+1,42');
    });

    test('imzali degisim negatif -> tire ile baslar', () {
      final s = TrFormat.signed(-1.42);
      expect(s.startsWith('-'), isTrue);
      expect(s, contains('1,42'));
    });

    test('imzasiz yuzde', () {
      expect(TrFormat.percent(1.42, withSign: false), '%1,42');
    });
  });

  group('TrFormat.dogruluk - null / NaN / Infinity', () {
    test('null para -> "—"', () {
      expect(TrFormat.money(null), TrFormat.noData);
    });

    test('NaN para -> "—"', () {
      expect(TrFormat.money(double.nan), TrFormat.noData);
    });

    test('Infinity para -> "—"', () {
      expect(TrFormat.money(double.infinity), TrFormat.noData);
    });

    test('NaN yuzde -> "—"', () {
      expect(TrFormat.percent(double.nan), TrFormat.noData);
    });

    test('NaN fiyat -> "—"', () {
      expect(TrFormat.price(double.nan), TrFormat.noData);
    });

    test('null tarih -> "—"', () {
      expect(TrFormat.date(null), TrFormat.noData);
      expect(TrFormat.dateTime(null), TrFormat.noData);
      expect(TrFormat.time(null), TrFormat.noData);
      expect(TrFormat.weekday(null), TrFormat.noData);
      expect(TrFormat.dateDot(null), TrFormat.noData);
      expect(TrFormat.relativeTime(null), TrFormat.noData);
    });

    test('isValid dogrulamasi', () {
      expect(TrFormat.isValid(1), isTrue);
      expect(TrFormat.isValid(0), isTrue);
      expect(TrFormat.isValid(double.nan), isFalse);
      expect(TrFormat.isValid(double.infinity), isFalse);
      expect(TrFormat.isValid(null), isFalse);
    });

    test('hicbir cikti "NaN" veya "Infinity" icermemeli', () {
      const samples = <num?>[
        double.nan,
        double.infinity,
        -double.infinity,
        null,
        0,
        -0.0,
        1e21,
        -1e21,
      ];
      for (final v in samples) {
        for (final out in [
          TrFormat.money(v),
          TrFormat.price(v),
          TrFormat.percent(v),
          TrFormat.signed(v),
          TrFormat.compact(v),
        ]) {
          expect(out.contains('NaN'), isFalse, reason: 'deger: $v -> $out');
          expect(out.contains('Infinity'), isFalse, reason: 'deger: $v -> $out');
        }
      }
    });
  });

  group('TrFormat.tarih / saat', () {
    test('2026-10-02 -> "2 Ekim 2026"', () {
      expect(TrFormat.date(DateTime(2026, 10, 2)), '2 Ekim 2026');
    });

    test('2026-01-15 14:32 -> "15 Ocak 2026, 14:32"', () {
      expect(
        TrFormat.dateTime(DateTime(2026, 1, 15, 14, 32)),
        '15 Ocak 2026, 14:32',
      );
    });

    test('saat padli "14:05"', () {
      expect(TrFormat.time(DateTime(2026, 1, 1, 14, 5)), '14:05');
    });

    test('2026-10-02 Cuma (rastgele degil)', () {
      expect(TrFormat.weekday(DateTime(2026, 10, 2)), 'Cuma');
    });

    test('nokta ile tarih "02.10.2026"', () {
      expect(TrFormat.dateDot(DateTime(2026, 10, 2)), '02.10.2026');
    });
  });

  group('TrFormat.gorece zaman', () {
    final now = DateTime(2026, 10, 2, 14, 0);

    test('60 saniyeden az -> "Az önce"', () {
      expect(
        TrFormat.relativeTime(now.subtract(const Duration(seconds: 30)),
            now: now),
        'Az önce',
      );
    });

    test('dakika -> "5 dk önce"', () {
      expect(
        TrFormat.relativeTime(now.subtract(const Duration(minutes: 5)),
            now: now),
        '5 dk önce',
      );
    });

    test('saat -> "3 saat önce"', () {
      expect(
        TrFormat.relativeTime(now.subtract(const Duration(hours: 3)),
            now: now),
        '3 saat önce',
      );
    });

    test('gun -> "2 gün önce"', () {
      expect(
        TrFormat.relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2 gün önce',
      );
    });

    test('gelecek tarih kati bicimde gosterilir', () {
      final future = now.add(const Duration(minutes: 10));
      expect(TrFormat.relativeTime(future, now: now), contains('2026'));
    });
  });

  group('TrFormat.kisa gosterim', () {
    test('milyon -> "1,20 Mn"', () {
      expect(TrFormat.compact(1200000), '1,20 Mn');
    });

    test('milyar -> "3,40 Mr"', () {
      expect(TrFormat.compact(3400000000), '3,40 Mr');
    });

    test('bin -> "1 B"', () {
      expect(TrFormat.compact(1200), '1 B');
    });
  });
}
