// Aşama 17 - Teknik görünüm ifadeleri.
//
// En kritik kural: **yatirim tavsiyesi / yargi yok**. Yalnizca olculmus
// durumun nesnel tarifi uretilir:
//   * "Fiyat EMA 50'nin üzerinde"      -> serbest
//   * "RSI 14 değeri 58"               -> serbest
//   * "Kesin yükselir" / "AL" / "SAT"  -> YASAK
//
// Bu test, uretilen **her** ifadeyi token token tarar.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/features/technical/technical_view.dart';

/// Yatirim tavsiyesi / yargi icerebilecek tek kelimelik yasaklar.
///
/// Not: "alış"/"satış" (makas bilgisi) bilincli olarak **yasak degildir**;
/// yalnizca tam olarak "al" ve "sat" tokenlari yasaktir.
const Set<String> _bannedTokens = {
  'al',
  'sat',
  'satın',
  'alın',
  'tavsiye',
  'tavsiyesi',
  'kesin',
  'kesinlikle',
  'güçlü',
  'zayıf',
  'öneri',
  'önerir',
  'yorum',
  'yükselir',
  'yükselmesi',
  'düşer',
  'düşmesi',
  'alınır',
  'satılır',
  'kaçının',
  'tutun',
};

/// Tum metinlerde asla gecmemesi gereken alt diziler.
const List<String> _bannedPhrases = [
  'kesin',
  'tavsiye',
  'güçlü',
  'zayıf',
  'yükselir',
  'düşer',
  'yukselir',
  'al/sat',
  'sat/al',
  'yatırım tavsiyesi',
  'garanti',
  'garantili',
];

/// Asla ekrana cikmamasi gereken teknik artiklar.
const List<String> _bannedArtifacts = ['NaN', 'null', 'undefined', 'Infinity'];

final _word = RegExp(r'\p{L}+', unicode: true);

List<String> _tokens(String s) =>
    _word.allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

void _expectClean(String text, String where) {
  for (final phrase in _bannedPhrases) {
    expect(
      text.toLowerCase().contains(phrase),
      isFalse,
      reason: '"$phrase" ifadede gecmemeli ($where): $text',
    );
  }
  for (final artifact in _bannedArtifacts) {
    expect(
      text.contains(artifact),
      isFalse,
      reason: '"$artifact" ifadede gecmemeli ($where): $text',
    );
  }
  final hit = _tokens(text).where(_bannedTokens.contains).toList();
  expect(
    hit,
    isEmpty,
    reason: 'yasak token(lar) $hit ifadede gecmemeli ($where): $text',
  );
  expect(text.trim().isEmpty, isFalse, reason: 'bos ifade uretilmis ($where)');
}

/// Sahte ama tutarli bir mum serisi - uydurma **piyasa verisi degil**,
/// yalnizca matematik dogrulamasi icin girdi.
List<Candle> _series(int n) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: DateTime.utc(2026, 6, 1).add(Duration(days: i)).millisecondsSinceEpoch,
          open: 100 + i * 0.4,
          high: 103 + i * 0.4,
          low: 98 + i * 0.4,
          close: 101 + i * 0.5,
          volume: (1000 + i * 13).toDouble(),
        ),
    ];

void main() {
  group('TechnicalViewEngine - nesnellik', () {
    test('uretilen tum ifadeler tavsiye/yargi icermemeli', () {
      final statements = TechnicalViewEngine.build(
        candles: _series(120),
        interval: ChartInterval.d1,
      );

      expect(statements, isNotEmpty, reason: 'ifade uretilmemis');

      for (final s in statements) {
        _expectClean(s.text, '1d / 120 mum');
      }
    });

    test('farkli zaman dilimlerinde de temiz', () {
      for (final interval in [
        ChartInterval.m15,
        ChartInterval.h1,
        ChartInterval.d1,
        ChartInterval.w1,
        ChartInterval.mo1,
      ]) {
        final statements = TechnicalViewEngine.build(
          candles: _series(60),
          interval: interval,
        );
        expect(statements, isNotEmpty, reason: '$interval bos dondu');
        for (final s in statements) {
          _expectClean(s.text, interval.name);
        }
      }
    });

    test('quote bilgisi eklendiginde de temiz', () {
      final statements = TechnicalViewEngine.build(
        candles: _series(80),
        interval: ChartInterval.d1,
        quote: Quote(
          assetId: 'usd-try',
          source: QuoteSourceLabel.otc,
          updatedAt: DateTime(2026, 10, 2, 12, 0),
          price: 49.14,
          previousClose: 48.97,
          dayHigh: 49.30,
          dayLow: 48.90,
          bid: 49.12,
          ask: 49.16,
        ),
      );

      expect(statements, isNotEmpty);
      for (final s in statements) {
        _expectClean(s.text, 'quote');
      }
    });
  });

  group('TechnicalViewEngine - icerik', () {
    test('RSI degeri nesnel olarak yazilir', () {
      final statements = TechnicalViewEngine.build(
        candles: _series(120),
        interval: ChartInterval.d1,
      );
      final rsi = statements.firstWhere(
        (s) => s.text.startsWith('RSI 14 değeri'),
        orElse: () => throw StateError('RSI ifadesi bulunamadi'),
      );
      expect(rsi.value, isNotNull);
      expect(rsi.value!, greaterThanOrEqualTo(0));
      expect(rsi.value!, lessThanOrEqualTo(100));
      expect(rsi.tone, StatementTone.neutral);
    });

    test('hareketli ortalama karsilastirmasi "üzerinde"/"altında" dili kullanir',
        () {
      final statements = TechnicalViewEngine.build(
        candles: _series(120),
        interval: ChartInterval.d1,
      );
      final comparisons = statements
          .where((s) => s.text.contains('SMA') || s.text.contains('EMA'))
          .toList();
      expect(comparisons, isNotEmpty);
      final hasRelation = comparisons.any(
        (s) => s.text.contains('üzerinde') || s.text.contains('altında'),
      );
      expect(hasRelation, isTrue);
    });

    test('quote verilince onceki kapanis karsilastirmasi eklenir', () {
      final statements = TechnicalViewEngine.build(
        candles: _series(80),
        interval: ChartInterval.d1,
        quote: Quote(
          assetId: 'usd-try',
          source: QuoteSourceLabel.otc,
          updatedAt: DateTime(2026, 10, 2, 12, 0),
          price: 50,
          previousClose: 48,
        ),
      );
      final vsPrev = statements
          .firstWhere((s) => s.text.contains('önceki kapanışa göre'));
      expect(vsPrev.value, isNotNull);
      expect(vsPrev.value!, closeTo(50 / 48 * 100 - 100, 1e-6));
    });

    test('dusuk mum sayisinda bos liste doner (uydurma ifade yok)', () {
      expect(
        TechnicalViewEngine.build(candles: _series(1), interval: ChartInterval.d1),
        isEmpty,
      );
      expect(
        TechnicalViewEngine.build(candles: const [], interval: ChartInterval.d1),
        isEmpty,
      );
    });

    test('gecersiz fiyat sifir/negatif ise ifade uretilmez', () {
      final bad = [
        Candle(
          time: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
          open: 0,
          high: 0,
          low: 0,
          close: 0,
        ),
        Candle(
          time: DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
          open: 0,
          high: 0,
          low: 0,
          close: 0,
        ),
      ];
      expect(
        TechnicalViewEngine.build(candles: bad, interval: ChartInterval.d1),
        isEmpty,
      );
    });

    test('tum ifadeler "." ile biter ve boslukla baslamaz', () {
      final statements = TechnicalViewEngine.build(
        candles: _series(120),
        interval: ChartInterval.d1,
      );
      for (final s in statements) {
        expect(s.text.endsWith('.'), isTrue, reason: s.text);
        expect(s.text.startsWith(' '), isFalse, reason: s.text);
        expect(s.text, isNot(contains('\n')));
      }
    });
  });
}
