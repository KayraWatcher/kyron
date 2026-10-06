import 'package:flutter_test/flutter_test.dart';

import 'package:gold/core/error/failures.dart';
import 'package:gold/data/canlidoviz/canlidoviz_protocol.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';

/// Unix saniye -> ISO (fixture uretimi icin yardimci).
String ts(DateTime dt) => '${dt.millisecondsSinceEpoch ~/ 1000}';

void main() {
  // Gercek endpoint'ten alinmis ornek yapisi: 1 dk'lik mumlar (:59'da biter).
  final barA = DateTime.utc(2026, 10, 6, 0, 0, 59);
  final barB = DateTime.utc(2026, 10, 6, 0, 1, 59);
  final barC = DateTime.utc(2026, 10, 6, 0, 2, 59);

  group('CanlidovizProtocol - varlik eslemesi', () {
    test('ons-altin -> itemDataId 12', () {
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.onsAltinId), 12);
    });

    test('dogrulanmis cid eslemeleri (canli API dogrulama 2026-10-06)', () {
      const expected = <String, int>{
        // Altin ailesi
        'ons-altin': 12,
        'gram-altin': 32,
        'ceyrek-altin': 11,
        'yarim-altin': 47,
        'tam-altin': 14,
        'cumhuriyet-altin': 27,
        'ata-altin': 58,
        'bilezik-22': 18,
        '14-ayar-altin': 16,
        '18-ayar-altin': 55,
        'resat-altin': 43,
        // Gumus
        'gram-gumus': 20,
        'ons-gumus': 267,
        // Doviz
        'usd-try': 1,
        'eur-try': 50,
        'gbp-try': 100,
        'chf-try': 51,
        'jpy-try': 57,
        'cad-try': 56,
        'aud-try': 102,
        'cny-try': 107,
        // Endeks
        'bist-100': 250,
        'bist-30': 248,
        'bist-50': 249,
        'dxy': 846,
        'sp-500': 1015,
        // Emtia
        'wti-crude': 1215,
        'brent-crude': 266,
        'platin': 268,
        // 1.2.0 genislemesi - emtia + kripto
        'paladyum': 269,
        'bakir': 1056,
        'dogalgaz': 1064,
        'platin-gram': 1012,
        'bitcoin': 62,
        'ethereum': 52,
      };
      expected.forEach((assetId, cid) {
        expect(CanlidovizProtocol.assetToItemId(assetId), cid,
            reason: '$assetId -> $cid');
      });
    });

    test('tum katalog varliklarinin cid eslemesi vardir (29 varlik)', () {
      for (final a in AssetCatalog.all) {
        expect(CanlidovizProtocol.assetToItemId(a.id), isNotNull,
            reason: '${a.id} icin cid dogrulanmali');
      }
      expect(CanlidovizProtocol.itemIdsByAsset, hasLength(AssetCatalog.all.length));
    });

    test('katalogda olmayan varlik -> null (uydurma cid YOK)', () {
      expect(CanlidovizProtocol.assetToItemId('unknown-asset'), isNull);
      expect(CanlidovizProtocol.assetToStreamCode('unknown-asset'), isNull);
      expect(CanlidovizProtocol.streamAssetIds, isNot(contains('unknown-asset')));
    });

    test('abonelik kodu mappingi: 23 kod (tik/kod kanitiyla)', () {
      const expected = <String, String>{
        'ons-altin': 'XAU/USD',
        'gram-altin': 'GA',
        'gram-gumus': 'GAG',
        'ceyrek-altin': 'C',
        'usd-try': 'USD',
        'eur-try': 'EUR',
        'gbp-try': 'GBP',
        'chf-try': 'CHF',
        'bist-100': 'XU100',
        'bist-30': 'XU030',
        'brent-crude': 'XBRUSD',
        'yarim-altin': 'Y',
        'tam-altin': 'T',
        'jpy-try': 'JPY',
        'cad-try': 'CAD',
        'aud-try': 'AUD',
        'cny-try': 'CNY',
        'ons-gumus': 'XAG/USD',
        'wti-crude': 'COIL',
        'platin': 'XPT/USD',
        'dxy': 'DXY',
        'sp-500': 'SPX',
        'bist-50': 'XU050',
        // 1.2.0 genislemesi
        'bitcoin': 'BTC',
        'ethereum': 'ETH',
        'paladyum': 'XPD/USD',
        'platin-gram': 'GRPLTN',
        'bakir': 'COPPER',
        'dogalgaz': 'NGAS',
      };
      expected.forEach((assetId, code) {
        expect(CanlidovizProtocol.assetToStreamCode(assetId), code,
            reason: '$assetId -> $code');
      });
      expect(CanlidovizProtocol.streamCodesByAsset, hasLength(expected.length));
      expect(CanlidovizProtocol.streamCodes, hasLength(expected.length));
    });

    test('kodu olmayan 4 altin urunu GOLD topic uyesi olarak akisa baglanir', () {
      expect(CanlidovizProtocol.streamTopics, ['GOLD']);
      expect(CanlidovizProtocol.streamTopicOnlyAssetIds, hasLength(4));

      for (final id in CanlidovizProtocol.streamTopicOnlyAssetIds) {
        // Topic uyesi: cid VARDIR, kodu YOKTUR.
        expect(CanlidovizProtocol.assetToItemId(id), isNotNull, reason: id);
        expect(CanlidovizProtocol.assetToStreamCode(id), isNull, reason: id);
        expect(CanlidovizProtocol.streamCodesByAsset.containsKey(id), isFalse);
      }
    });

    test('streamAssetIds = kodlu varliklar + 4 topic uyesi', () {
      expect(
        CanlidovizProtocol.streamAssetIds,
        hasLength(
          CanlidovizProtocol.streamCodesByAsset.length +
              CanlidovizProtocol.streamTopicOnlyAssetIds.length,
        ),
      );
      expect(
        CanlidovizProtocol.streamAssetIds,
        containsAll(CanlidovizProtocol.streamTopicOnlyAssetIds),
      );
    });

    test('subscriptionFrame kod + topic alanini birlikte gonderir', () {
      expect(
        CanlidovizProtocol.subscriptionFrame(['XAU/USD'], topics: ['GOLD']),
        '42["us",{"t":["GOLD"],"c":["XAU/USD"],"m":false}]',
      );
      // Topic verilmezse eski bicim korunur (t bos dizi).
      expect(
        CanlidovizProtocol.subscriptionFrame(['XAU/USD']),
        '42["us",{"t":[],"c":["XAU/USD"],"m":false}]',
      );
    });
  });

  group('1+2+3+4) OHLC response parse / alan sirasi / timestamp', () {
    // open=0, high=1, low=2, close=3 (c.bundle.js -> parsePipe ile dogrulandi).
    test('gecerli yanit mumlari dogru alanlarla dondurur', () {
      final json = '{'
          '"${ts(barA)}":"4133.10|4134.02|4132.90|4133.75",'
          '"${ts(barB)}":"4133.75|4135.10|4133.60|4134.90",'
          '"${ts(barC)}":"4134.90|4135.20|4134.10|4134.55"'
          '}';

      final result = CanlidovizProtocol.parseHistory(json);
      expect(result.isSuccess, isTrue);

      final candles = result.dataOrNull!;
      expect(candles, hasLength(3));

      // 4) open/high/low/close maplemesi
      final first = candles.first;
      expect(first.open, 4133.10);
      expect(first.high, 4134.02);
      expect(first.low, 4132.90);
      expect(first.close, 4133.75);
      expect(first.volume, isNull); // kaynakta hacim yok -> uydurulmaz

      // 3) timestamp: Unix saniye -> milisaniye (UTC)
      expect(first.time, barA.millisecondsSinceEpoch);
      expect(
        DateTime.fromMillisecondsSinceEpoch(first.time, isUtc: true),
        barA,
      );

      // siralama artan olmali
      expect(candles.map((c) => c.time).toList(), [
        for (final d in [barA, barB, barC]) d.millisecondsSinceEpoch,
      ]);
    });

    test('DAILY response parse (gunluk barlar)', () {
      final day1 = DateTime.utc(2026, 10, 5);
      final day2 = DateTime.utc(2026, 10, 6);
      final json = '{'
          '"${ts(day2)}":"4141.11|4170.72|4123.63|4140.46",'
          '"${ts(day1)}":"4120.00|4150.00|4110.00|4141.11"'
          '}';

      final result = CanlidovizProtocol.parseHistory(json);
      expect(result.isSuccess, isTrue);

      final candles = result.dataOrNull!;
      expect(candles, hasLength(2));
      expect(candles.first.time, day1.millisecondsSinceEpoch);
      expect(candles.first.close, 4141.11);
      expect(candles.last.time, day2.millisecondsSinceEpoch);
      expect(candles.last.open, 4141.11);
      expect(candles.last.close, 4140.46);
    });
  });

  group('5+6+7) gecersiz yanit / gecersiz sayi / high<low', () {
    test('JSON olmayan govde -> ParseFailure', () {
      final r = CanlidovizProtocol.parseHistory('not valid json');
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<ParseFailure>());
    });

    test('HTML govde -> ParseFailure', () {
      final r = CanlidovizProtocol.parseHistory('<html><body>error</body></html>');
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<ParseFailure>());
    });

    test('JSON liste -> ParseFailure', () {
      final r = CanlidovizProtocol.parseHistory('[1,2,3]');
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<ParseFailure>());
    });

    test('sunucu hata govdesi -> BadRequestFailure + mesaj', () {
      const body = '{"data":null,"message":"invalid date range"}';
      final r = CanlidovizProtocol.parseHistory(body);
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<BadRequestFailure>());
      expect(r.failureOrNull!.message, contains('invalid date range'));
    });

    test('bos obje -> EmptyFailure', () {
      final r = CanlidovizProtocol.parseHistory('{}');
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('hic gecersiz olmayan mum iceren yanit -> EmptyFailure', () {
      const body = '{"abc":"1|2|3|4","100":"x"}';
      final r = CanlidovizProtocol.parseHistory(body);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('gecersiz sayi alanlari mumu dusurur', () {
      final key = ts(barA);
      const invalid = <String, String>{
        'metin': 'abc|100|90|95', // open sayisal degil
        'eksik': '100|90|95', // 3 alan
        'bos': '',
        'nan': 'NaN|100|90|95',
        'sonsuz': '100|Infinity|90|95',
        'negatif': '-1|100|90|95',
        'sifir': '0|0|0|0',
        'bosDeger': '100||90|95',
      };

      for (final entry in invalid.entries) {
        final body = '{"$key":"${entry.value}"}';
        final r = CanlidovizProtocol.parseHistory(body);
        expect(r.isFailure, isTrue, reason: '${entry.key} kabul edilmemeli');
        expect(r.failureOrNull, isA<EmptyFailure>(), reason: entry.key);
      }

      // Ayni anahtarda tek GECERLI mum varsa yanit basarili kalmali.
      final ok = CanlidovizProtocol.parseHistory(
        '{"$key":"abc","${ts(barB)}":"4133.75|4135.10|4133.60|4134.90"}',
      );
      expect(ok.isSuccess, isTrue);
      expect(ok.dataOrNull, hasLength(1));
    });

    test('null deger -> mum dusurulur', () {
      final body = '{"${ts(barA)}":null}';
      final r = CanlidovizProtocol.parseHistory(body);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('high < low -> mum reddedilir', () {
      final body = '{"${ts(barA)}":"100|100|200|150"}'; // high=100 < low=200
      final r = CanlidovizProtocol.parseHistory(body);
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('parseCandle: gecersiz timestamp -> null', () {
      expect(CanlidovizProtocol.parseCandle('abc', '1|2|0.5|1.5'), isNull);
      expect(CanlidovizProtocol.parseCandle('0', '1|2|0.5|1.5'), isNull);
      expect(CanlidovizProtocol.parseCandle('-5', '1|2|0.5|1.5'), isNull);
      // 2100-01-01 sonrasi
      expect(CanlidovizProtocol.parseCandle('4102444801', '1|2|0.5|1.5'), isNull);
      expect(CanlidovizProtocol.parseCandle('4102444800', '1|2|0.5|1.5'), isNotNull);
    });
  });

  group('11) interval -> period mapping', () {
    test('m1..h4 -> OHLC', () {
      for (final i in [
        ChartInterval.m1,
        ChartInterval.m5,
        ChartInterval.m15,
        ChartInterval.m30,
        ChartInterval.h1,
        ChartInterval.h4,
      ]) {
        expect(CanlidovizProtocol.periodFor(i), 'OHLC', reason: i.name);
      }
    });

    test('d1/w1/mo1 -> DAILY', () {
      for (final i in [
        ChartInterval.d1,
        ChartInterval.w1,
        ChartInterval.mo1,
      ]) {
        expect(CanlidovizProtocol.periodFor(i), 'DAILY', reason: i.name);
      }
    });
  });

  group('12) tarih bicimi', () {
    test('yyyy-MM-ddTHH:mm:ss (UTC)', () {
      expect(
        CanlidovizProtocol.formatTimestamp(DateTime.utc(2026, 10, 6, 9, 5, 3)),
        '2026-10-06T09:05:03',
      );
      expect(
        CanlidovizProtocol.formatTimestamp(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '2026-01-02T03:04:05',
      );
    });

    test('yerel saatli DateTime da UTC anina gore bicimlenir', () {
      final utc = DateTime.utc(2026, 3, 1, 14, 30, 45);
      expect(CanlidovizProtocol.formatTimestamp(utc.toLocal()),
          '2026-03-01T14:30:45');
    });

    test('historyUri kanitlanmis query bicimini uretir (: kodlanmaz)', () {
      final uri = CanlidovizProtocol.historyUri(
        period: 'OHLC',
        itemDataId: 12,
        startUtc: DateTime.utc(2026, 10, 5, 0, 0, 0),
        endUtc: DateTime.utc(2026, 10, 6, 0, 0, 0),
      );

      expect(uri.toString(),
          'https://a.canlidoviz.com/items/history?period=OHLC&itemDataId=12'
          '&startDate=2026-10-05T00:00:00&endDate=2026-10-06T00:00:00');
      expect(uri.toString(), isNot(contains('%3A')));
      expect(uri.queryParameters['period'], 'OHLC');
      expect(uri.queryParameters['itemDataId'], '12');
    });
  });

  group('13) retansiyon / aralik davranisi', () {
    test('OHLC penceresi emniyet tavaniyla sinirli', () {
      // m1: 300 dk = 5 saat (tavan alti)
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.m1, 300),
        const Duration(minutes: 300),
      );
      // m5: 300 * 5 dk = 25 saat
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.m5, 300),
        const Duration(hours: 25),
      );
      // h1: 300 * 1 sa = 300 saat (12.5 gun - tavan alti)
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.h1, 300),
        const Duration(hours: 300),
      );
      // h4: 300 * 4 sa = 1200 saat (50 gun) -> 25 gun tavani devrede.
      // (29+ gunluk istek sunucudan 400 donuyor.)
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.h4, 300),
        CanlidovizProtocol.ohlcMaxWindow,
      );
      expect(CanlidovizProtocol.ohlcMaxWindow, const Duration(days: 25));
    });

    test('DAILY penceresi tavani', () {
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.d1, 300),
        const Duration(days: 300),
      );
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.w1, 300),
        const Duration(days: 2100),
      );
      // mo1: 300 * 30 gun = 9000 gun -> 3650 gun tavani devrede.
      expect(
        CanlidovizProtocol.windowFor(ChartInterval.mo1, 300),
        CanlidovizProtocol.dailyMaxWindow,
      );
    });

    test('retansiyon asiminda veri UYDURULMAZ (eksik doner)', () {
      // h4 istegi en fazla ~8 gunluk retansiyon verisi alir; kaynakta olmayan
      // bar uretilmez, seri `limit`'e PADLANMAZ - bu davranis prepare/
      // takeLast tarafinda korunur. 42 dakikalik gercek mum -> 1 adet
      // 4 saatlik kova (dolayisiyla 42 degil, 1 bar doner).
      final raw = [for (var i = 0; i < 42; i++) _bar(i)];
      final out = CanlidovizProtocol.prepare(raw, ChartInterval.h4, 300);

      expect(out, isNotEmpty);
      expect(out.length, lessThanOrEqualTo(300));
      expect(out, hasLength(1));
      expect(out.first.open, raw.first.open);
      expect(out.last.close, raw.last.close);
      expect(out.first.time, DateTime.utc(2026, 10, 6).millisecondsSinceEpoch);
    });
  });

  group('14) limit + aggregasyon', () {
    test('takeLast en yenileri tutar', () {
      final src = [for (var i = 0; i < 10; i++) _bar(i)];
      final out = CanlidovizProtocol.takeLast(src, 3);
      expect(out, hasLength(3));
      expect(out.first.time, src[7].time);
      expect(out.last.time, src[9].time);
      // limit buyukse ayni liste doner
      expect(CanlidovizProtocol.takeLast(src, 50), hasLength(10));
    });

    test('m1 ve d1 kaynaga dokunmaz', () {
      final src = [for (var i = 0; i < 5; i++) _bar(i)];
      expect(
        CanlidovizProtocol.aggregateFor(src, ChartInterval.m1),
        hasLength(5),
      );
      expect(
        CanlidovizProtocol.aggregateFor(src, ChartInterval.d1),
        hasLength(5),
      );
      // tum degerler aynen korunur
      final out = CanlidovizProtocol.aggregateFor(src, ChartInterval.m1);
      expect(out.first.open, src.first.open);
      expect(out.last.close, src.last.close);
    });

    test('m5: 1 dk barlari 5 dk kovalarina birlesir (kaynak degerlerle)', () {
      // 00:00:59 .. 00:09:59 arasi 10 bar -> 2 kova (00:00 ve 00:05).
      final src = <Candle>[
        for (var i = 0; i < 10; i++)
          Candle(
            time: DateTime.utc(2026, 10, 6, 0, i, 59).millisecondsSinceEpoch,
            open: (100 + i).toDouble(),
            high: (200 + i).toDouble(),
            low: (50 + i).toDouble(),
            close: (150 + i).toDouble(),
          ),
      ];

      final out = CanlidovizProtocol.prepare(src, ChartInterval.m5, 300);
      expect(out, hasLength(2));

      // ilk kova: bar 0..4
      expect(out[0].open, 100); // ilk barin acilisi
      expect(out[0].high, 204); // en buyuk yukseklik
      expect(out[0].low, 50); // en kucuk dip
      expect(out[0].close, 154); // son barin kapanisi

      // ikinci kova: bar 5..9
      expect(out[1].open, 105);
      expect(out[1].high, 209);
      expect(out[1].low, 55);
      expect(out[1].close, 159);

      expect(
        out[0].time,
        DateTime.utc(2026, 10, 6).millisecondsSinceEpoch,
      ); // kova BASLANGICI
    });

    test('prepare limit asiminda en yenileri tutar', () {
      final src = [for (var i = 0; i < 10; i++) _bar(i)];
      final out = CanlidovizProtocol.prepare(src, ChartInterval.m1, 4);
      expect(out, hasLength(4));
      expect(out.last.time, src.last.time);
    });
  });
}

/// 1 dk'lik referans bar (zaman keyfi artar, OHLC degerleri bar indeksine bagli).
Candle _bar(int i) => Candle(
      time: DateTime.utc(2026, 10, 6, 0, i, 59).millisecondsSinceEpoch,
      open: (100 + i).toDouble(),
      high: (110 + i).toDouble(),
      low: (90 + i).toDouble(),
      close: (105 + i).toDouble(),
    );
