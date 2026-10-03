// Aşama 17 - Alarm kosullari (saf degerlendirici).
//
// Kurallar:
//  * `null` / `NaN` fiyatla **asla** karar verilmez.
//  * Kosul `>` / `<` (esitlik tetiklemez), yuzde alarminda `>=` / `<=`.
//  * Zaten tetiklenmis alarm tekrar bildirilmez.
//  * Onceden gorulmus haber tekrar bildirilmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/alerts/alert_evaluator.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:gold/domain/entities/price_alert.dart';
import 'package:gold/domain/entities/quote.dart';

Quote _q({
  double? price,
  double? changePercent,
  double? dayHigh,
  double? dayLow,
}) =>
    Quote(
      assetId: 'usd-try',
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 2, 12, 0),
      price: price,
      changePercent: changePercent,
      dayHigh: dayHigh,
      dayLow: dayLow,
    );

PriceAlert _alert(
  AlertType type, {
  double? threshold,
  double? percent,
  AlertDirection direction = AlertDirection.above,
  bool enabled = true,
  DateTime? triggeredAt,
  String assetId = 'usd-try',
}) =>
    PriceAlert(
      type: type,
      assetId: assetId,
      threshold: threshold,
      percent: percent,
      direction: direction,
      enabled: enabled,
      triggeredAt: triggeredAt,
    );

NewsItem _news(String id, NewsCategory cat, String title) => NewsItem(
      id: id,
      title: title,
      source: 'Test Kaynak',
      publishedAt: DateTime(2026, 10, 2),
      category: cat,
      url: 'https://example.com/$id',
    );

void main() {
  group('AlertEvaluator - fiyat alarmlari', () {
    test('fiyat esik uzerinde -> kosul saglanir', () {
      final a = _alert(AlertType.priceAbove, threshold: 100);
      expect(AlertEvaluator.conditionMet(a, _q(price: 105)), isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 99)), isFalse);
    });

    test('esitlik tetiklemez (strict)', () {
      final above = _alert(AlertType.priceAbove, threshold: 100);
      final below = _alert(AlertType.priceBelow, threshold: 100);
      final q = _q(price: 100);
      expect(AlertEvaluator.conditionMet(above, q), isFalse);
      expect(AlertEvaluator.conditionMet(below, q), isFalse);
    });

    test('fiyat altinda -> alt kosulu saglanir', () {
      final a = _alert(AlertType.priceBelow, threshold: 100);
      expect(AlertEvaluator.conditionMet(a, _q(price: 95)), isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 105)), isFalse);
    });

    test('kosul saglaninca bildirim metni uretilir', () {
      final a = _alert(AlertType.priceAbove, threshold: 100);
      final r = AlertEvaluator.evaluate(a, _q(price: 105));
      expect(r.fire, isTrue);
      expect(r.message, isNotEmpty);
      expect(r.message, contains('105'));
      expect(r.message.toLowerCase(), contains('üzerine'));
      expect(r.message.contains('NaN'), isFalse);
    });
  });

  group('AlertEvaluator - yuzde alarmlari', () {
    test('yukari yon: % degisim esigi gecer', () {
      final a = _alert(
        AlertType.percentChange,
        percent: 2,
        direction: AlertDirection.above,
      );
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: 3)),
          isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: 1.9)),
          isFalse);
      // Esitlik burada tetikler (>=).
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: 2)),
          isTrue);
    });

    test('asagi yon: negatif % esigi gecer', () {
      final a = _alert(
        AlertType.percentChange,
        percent: 2,
        direction: AlertDirection.below,
      );
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: -3)),
          isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: -1)),
          isFalse);
      expect(AlertEvaluator.conditionMet(a, _q(price: 100, changePercent: 3)),
          isFalse);
    });

    test('yuzde verisi yoksa karar verilmez', () {
      final a = _alert(AlertType.percentChange, percent: 2);
      expect(AlertEvaluator.conditionMet(a, _q(price: 100)), isFalse);
      expect(AlertEvaluator.conditionMet(a, null), isFalse);
    });
  });

  group('AlertEvaluator - gunluk tepe/dip', () {
    test('gunluk en yuksege ulasir', () {
      final a = _alert(AlertType.dayHigh);
      expect(AlertEvaluator.conditionMet(a, _q(price: 110, dayHigh: 110)),
          isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 109, dayHigh: 110)),
          isFalse);
    });

    test('gunluk en dusuge iner', () {
      final a = _alert(AlertType.dayLow);
      expect(AlertEvaluator.conditionMet(a, _q(price: 90, dayLow: 90)), isTrue);
      expect(AlertEvaluator.conditionMet(a, _q(price: 91, dayLow: 90)),
          isFalse);
    });

    test('kaynakta tepe/dip yoksa karar verilmez', () {
      expect(
        AlertEvaluator.conditionMet(
          _alert(AlertType.dayHigh),
          _q(price: 110),
        ),
        isFalse,
      );
      expect(
        AlertEvaluator.conditionMet(
          _alert(AlertType.dayLow),
          _q(price: 90),
        ),
        isFalse,
      );
    });
  });

  group('AlertEvaluator - gecersiz veri asla bildirim uretmez', () {
    test('fiyat null -> hicbir fiyat alarmi tetiklenmez', () {
      final q = _q();
      expect(AlertEvaluator.conditionMet(_alert(AlertType.priceAbove), q),
          isFalse);
      expect(
          AlertEvaluator.conditionMet(_alert(AlertType.priceBelow), q), isFalse);
      expect(AlertEvaluator.conditionMet(_alert(AlertType.dayHigh), q), isFalse);
      expect(AlertEvaluator.conditionMet(_alert(AlertType.dayLow), q), isFalse);
      expect(AlertEvaluator.evaluate(_alert(AlertType.priceAbove), q).fire,
          isFalse);
    });

    test('NaN fiyat -> hasPrice false -> bildirim yok', () {
      final q = _q(price: double.nan);
      expect(q.hasPrice, isFalse);
      expect(
        AlertEvaluator.conditionMet(
          _alert(AlertType.priceAbove, threshold: 1),
          q,
        ),
        isFalse,
      );
    });

    test('esik tanimsiz (null) -> alarm gecersiz, degerlendirilmez', () {
      final a = _alert(AlertType.priceAbove);
      expect(a.isValid, isFalse);
      expect(a.isArmed, isFalse);
      expect(AlertEvaluator.conditionMet(a, _q(price: 999)), isFalse);
      expect(AlertEvaluator.evaluate(a, _q(price: 999)).fire, isFalse);
    });

    test('quote null -> karar verilmez', () {
      expect(
        AlertEvaluator.conditionMet(
          _alert(AlertType.priceAbove, threshold: 1),
          null,
        ),
        isFalse,
      );
      expect(
        AlertEvaluator.evaluate(_alert(AlertType.priceAbove, threshold: 1), null)
            .fire,
        isFalse,
      );
    });

    test('kapali alarm degerlendirilmez', () {
      final a = _alert(AlertType.priceAbove, threshold: 1, enabled: false);
      expect(AlertEvaluator.conditionMet(a, _q(price: 100)), isFalse);
      expect(AlertEvaluator.evaluate(a, _q(price: 100)).fire, isFalse);
    });

    test('oneceden tetiklenmis alarm tekrar bildirilmez', () {
      final a = _alert(
        AlertType.priceAbove,
        threshold: 100,
        triggeredAt: DateTime(2026, 10, 2),
      );
      // Kosul hala saglanir...
      expect(AlertEvaluator.conditionMet(a, _q(price: 105)), isTrue);
      // ...ama tekrar bildirim yapilmaz.
      final r = AlertEvaluator.evaluate(a, _q(price: 105));
      expect(r.fire, isFalse);
      expect(r.message, isEmpty);
    });
  });

  group('AlertEvaluator - onemli haber', () {
    final alert = PriceAlert(
      type: AlertType.importantNews,
      newsCategory: 'ekonomi',
    );

    test('gorsel/veri alarmi olarak hic degerlendirilmez', () {
      expect(AlertEvaluator.conditionMet(alert, _q(price: 1)), isFalse);
      expect(AlertEvaluator.evaluate(alert, _q(price: 1)).fire, isFalse);
    });

    test('gorulmemis uygun haber bildirim uretir', () {
      final r = AlertEvaluator.evaluateNews(
        alert: alert,
        items: [_news('n1', NewsCategory.ekonomi, 'TCMB faizi sabit tuttu')],
        seenNewsIds: const {},
      );
      expect(r.fire, isTrue);
      expect(r.message, contains('TCMB faizi sabit tuttu'));
      expect(r.message, contains('Test Kaynak'));
    });

    test('gorulmus haber tekrar bildirilmez', () {
      final r = AlertEvaluator.evaluateNews(
        alert: alert,
        items: [_news('n1', NewsCategory.ekonomi, 'Baslik')],
        seenNewsIds: const {'n1'},
      );
      expect(r.fire, isFalse);
    });

    test('kategori disi haber bildirilmez', () {
      final r = AlertEvaluator.evaluateNews(
        alert: alert,
        items: [_news('n1', NewsCategory.borsa, 'Borsa haberi')],
        seenNewsIds: const {},
      );
      expect(r.fire, isFalse);
    });

    test('kategori etiketi (Buyuk harfli) de kabul edilir', () {
      final byLabel = PriceAlert(
        type: AlertType.importantNews,
        newsCategory: 'Borsa',
      );
      final r = AlertEvaluator.evaluateNews(
        alert: byLabel,
        items: [_news('n2', NewsCategory.borsa, 'Borsa haberi')],
        seenNewsIds: const {},
      );
      expect(r.fire, isTrue);
    });

    test('kategori belirtilmemis ise tum haberler kabul edilir', () {
      final any = PriceAlert(type: AlertType.importantNews);
      final r = AlertEvaluator.evaluateNews(
        alert: any,
        items: [_news('n3', NewsCategory.altin, 'Altın fırladı')],
        seenNewsIds: const {},
      );
      expect(r.fire, isTrue);
    });

    test('bos listede bildirim uretilmez', () {
      final r = AlertEvaluator.evaluateNews(
        alert: alert,
        items: const [],
        seenNewsIds: const {},
      );
      expect(r.fire, isFalse);
    });
  });

  group('PriceAlert - JSON donusumu', () {
    test('gecerli alarm JSON -> nesne -> JSON', () {
      final a = _alert(
        AlertType.percentChange,
        percent: 3.5,
        direction: AlertDirection.below,
      );
      final back = PriceAlert.fromJson(a.toJson());
      expect(back, isNotNull);
      expect(back!.type, AlertType.percentChange);
      expect(back.percent, 3.5);
      expect(back.direction, AlertDirection.below);
      expect(back.assetId, 'usd-try');
    });

    test('taninmayan turden alarm uretilmez', () {
      expect(
        PriceAlert.fromJson(const {'type': 'gecersiz-tur', 'assetId': 'x'}),
        isNull,
      );
    });

    test('kosulu eksik alarm uretilmez', () {
      expect(
        PriceAlert.fromJson(const {'type': 'priceAbove', 'assetId': 'x'}),
        isNull,
      );
      expect(PriceAlert.fromJson(const {'type': 'dayHigh'}), isNull);
    });

    test('bozuk JSON firlatmaz, null dondurur', () {
      expect(PriceAlert.fromJson(const {}), isNull);
      expect(
        PriceAlert.fromJson(const {'type': 'priceAbove', 'threshold': 'abc'}),
        isNull,
      );
    });
  });
}
