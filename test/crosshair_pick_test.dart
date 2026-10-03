// V2 - gereksinim 4 ve 5: grafikte gecmise kaydirildiginda **ustteki ana
// fiyat** da o tarihin fiyatina gecmeli; ayni zamanda serinin disina cikan
// bir mum asla uydurulmamali (sahte veri yok).
//
// Bu dosya saf (pure) cozumleme katmanini test eder: ekrandan bagimsizdir,
// ag gerektirmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/features/asset_detail/asset_detail_providers.dart';

Candle _c(int time, double close) => Candle(
      time: time,
      open: close,
      high: close + 1,
      low: close - 1,
      close: close,
      volume: 100,
    );

void main() {
  final serI = <Candle>[
    _c(1000, 10),
    _c(2000, 20),
    _c(3000, 30),
  ];

  group('resolveCrosshairCandle', () {
    test('imlec kapali (null) -> null: ust baslik canli modda kalir', () {
      expect(resolveCrosshairCandle(serI, null), isNull);
    });

    test('gecerli indeks -> serideki o mumun kendisi (uydurulmaz)', () {
      final picked = resolveCrosshairCandle(serI, 1);
      expect(picked, same(serI[1]));
      expect(picked!.close, 20);
      expect(picked.time, 2000);
    });

    test('ilk ve son indeks serinin disina cikmaz', () {
      expect(resolveCrosshairCandle(serI, 0), same(serI.first));
      expect(resolveCrosshairCandle(serI, 2), same(serI.last));
    });

    test('ust sinir disi -> SON mum (sagda bos alan icin uydurulmaz)', () {
      expect(resolveCrosshairCandle(serI, 99), same(serI.last));
      expect(resolveCrosshairCandle(serI, 3), same(serI.last));
    });

    test('alt sinir disi -> ILK mum', () {
      expect(resolveCrosshairCandle(serI, -1), same(serI.first));
      expect(resolveCrosshairCandle(serI, -999), same(serI.first));
    });

    test('bos seri -> null (veri yokken deger uydurulmaz)', () {
      expect(resolveCrosshairCandle(const <Candle>[], 0), isNull);
      expect(resolveCrosshairCandle(const <Candle>[], 5), isNull);
    });

    test('tek mumluk seri disindaki her indeks o mume sikistirilir', () {
      final tek = <Candle>[_c(5000, 42)];
      expect(resolveCrosshairCandle(tek, 0), same(tek.single));
      expect(resolveCrosshairCandle(tek, 7), same(tek.single));
      expect(resolveCrosshairCandle(tek, -7), same(tek.single));
    });
  });

  group('crosshairChanged', () {
    test('null -> null: degisiklik degil (zaten canli moda gecilmis)', () {
      expect(crosshairChanged(null, null), isFalse);
    });

    test('canli -> ilk mum: degisiklik (ust baslik tarihe gecer)', () {
      expect(crosshairChanged(null, serI.first), isTrue);
    });

    test('mum -> canli: degisiklik (imlec kalkti, canli fiyat doner)', () {
      expect(crosshairChanged(serI.first, null), isTrue);
    });

    test('ayni mumun icinde gezmek ust basligi yeniden kurmaz', () {
      expect(crosshairChanged(serI[1], serI[1]), isFalse);
      expect(crosshairChanged(serI[1], _c(2000, 20)), isFalse);
    });

    test('farkli bir muma gecis ust basligi yeniden kurar', () {
      expect(crosshairChanged(serI[1], serI[2]), isTrue);
      expect(crosshairChanged(serI[2], serI[0]), isTrue);
    });

    test('ayni tarih, farkli kapanis (canli mum) -> yeniden kurulur', () {
      final tazelenmis = _c(2000, 25);
      expect(crosshairChanged(serI[1], tazelenmis), isTrue);
    });
  });
}
