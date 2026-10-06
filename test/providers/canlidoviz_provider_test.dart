import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/data/canlidoviz/canlidoviz_protocol.dart';
import 'package:gold/data/canlidoviz/canlidoviz_socket.dart';
import 'package:gold/data/providers/canlidoviz_provider.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

/// Anlik akis sahtesi - gercek WebSocket ACILMAZ.
class FakeStream implements CanlidovizPriceStream {
  final Map<int, CanlidovizTick> ticks = <int, CanlidovizTick>{};

  @override
  void start() {}

  @override
  void stop() {}

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  CanlidovizTick? latest(int cid) => ticks[cid];
}

/// Gercek endpoint'in yanit yapisi: `{unixTs: "o|h|l|c"}`.
/// Barlar 1 dk'lik ve `:59`'da biter (ag analizinde gozlenen bicim).
String ohlcBody({int count = 5}) {
  final buf = StringBuffer('{');
  for (var i = 0; i < count; i++) {
    final t = DateTime.utc(2026, 10, 6, 0, i, 59).millisecondsSinceEpoch ~/ 1000;
    buf.write('"$t":"${100 + i}|${110 + i}|${90 + i}|${105 + i}"');
    if (i != count - 1) buf.write(',');
  }
  buf.write('}');
  return buf.toString();
}

/// Gunluk kapanis yaniti (DAILY period).
String dailyBody({required DateTime day, double close = 4140.46}) {
  final t = day.millisecondsSinceEpoch ~/ 1000;
  return '{"$t":"${close - 1}|${close + 1}|${close - 2}|$close"}';
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(<String, String>{});
  });

  group('CanlidovizProvider', () {
    late CanlidovizProvider provider;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      provider = CanlidovizProvider(httpClient: mockClient);
    });

    tearDown(() => provider.dispose());

    Uri capturedUri() => verify(
          () => mockClient.get(captureAny(), headers: any(named: 'headers')),
        ).captured.first as Uri;

    List<Uri> capturedUris() => verify(
          () => mockClient.get(captureAny(), headers: any(named: 'headers')),
        ).captured.cast<Uri>();

    void stubBody(String body, {int status = 200}) {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(body, status));
    }

    group('kimlik', () {
      test('id / displayName / refreshInterval', () {
        expect(provider.id, 'canlidoviz');
        expect(provider.displayName, 'CanlıDöviz');
        expect(provider.refreshInterval, const Duration(seconds: 60));
      });
    });

    group('(8+10) supports - akis (quote) destegi', () {
      test('kodlu varliklar -> true (altin/doviz/endeks/emtia)', () {
        const streamable = [
          AssetCatalog.onsAltinId,
          AssetCatalog.gramAltinId,
          AssetCatalog.gramGumusId,
          AssetCatalog.ceyrekAltinId,
          AssetCatalog.yarimAltinId,
          AssetCatalog.tamAltinId,
          AssetCatalog.onsGumusId,
          AssetCatalog.usdTryId,
          AssetCatalog.eurTryId,
          AssetCatalog.gbpTryId,
          AssetCatalog.chfTryId,
          AssetCatalog.jpyTryId,
          AssetCatalog.cadTryId,
          AssetCatalog.audTryId,
          AssetCatalog.cnyTryId,
          AssetCatalog.bist100Id,
          AssetCatalog.bist30Id,
          AssetCatalog.bist50Id,
          AssetCatalog.dxyId,
          AssetCatalog.sp500Id,
          AssetCatalog.brentCrudeId,
          AssetCatalog.wtiCrudeId,
          AssetCatalog.platinId,
        ];
        for (final id in streamable) {
          expect(provider.supports(id), isTrue, reason: id);
        }
      });

      test('GOLD topic uyesi, kodu olmayan varliklar -> true', () {
        for (final id in CanlidovizProtocol.streamTopicOnlyAssetIds) {
          expect(provider.supports(id), isTrue, reason: id);
        }
      });

      test('akisa baglanmayanlar -> false (14/18 ayar = yalnizca mum)', () {
        expect(provider.supports(AssetCatalog.ayar14AltinId), isFalse);
        expect(provider.supports(AssetCatalog.ayar18AltinId), isFalse);
        expect(provider.supports('unknown-asset'), isFalse);
      });

      test('supports icin akis uyesi sayisi = kodlar + topic uyeleri', () {
        expect(
          AssetCatalog.all.where((a) => provider.supports(a.id)).length,
          CanlidovizProtocol.streamCodesByAsset.length +
              CanlidovizProtocol.streamTopicOnlyAssetIds.length,
          reason: '14/18 ayar disinda her varlik akisa baglidir',
        );
      });
    });

    group('(9+10) supportsCandles - mum (history API) destegi', () {
      test('cid eslemesi olan TUM varliklar -> true', () {
        for (final a in AssetCatalog.all) {
          expect(provider.supportsCandles(a.id), isTrue, reason: a.id);
        }
        expect(
          AssetCatalog.all.where((a) => provider.supportsCandles(a.id)).length,
          CanlidovizProtocol.itemIdsByAsset.length,
        );
      });

      test('14/18 ayar icin mum destegi var (quote destegi YOK)', () {
        expect(provider.supportsCandles(AssetCatalog.ayar14AltinId), isTrue);
        expect(provider.supports(AssetCatalog.ayar14AltinId), isFalse);
      });

      test('katalog disi varlik -> false', () {
        expect(provider.supportsCandles('unknown-asset'), isFalse);
      });
    });

    group('fetchQuotes (akis yokken fiyat vermez)', () {
      test('EmptyFailure dondurur ve AG CAGRISI YAPMAZ', () async {
        final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(r.isFailure, isTrue);
        expect(r.failureOrNull, isA<EmptyFailure>());
        verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
      });
    });

    group('previousClose (degisim yuzdesi gercek kapanistan)', () {
      late FakeStream stream;

      setUp(() {
        stream = FakeStream();
        stream.ticks[12] = CanlidovizTick(
          cid: 12,
          bid: 4115.16,
          ask: 4115.43,
          receivedAt: DateTime.now(),
        );
        provider = CanlidovizProvider(
          httpClient: mockClient,
          priceStream: stream,
        );
      });

      test('DAILY kapanis arka planda cekilir ve quote\'a eklenir', () async {
        final now = DateTime.now().toUtc();
        final yesterday = DateTime.utc(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
        stubBody(dailyBody(day: yesterday, close: 4140.46));

        // 1. okuma: tik aninda gelir, kapanis henuz arka planda cekiliyor.
        final first = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(first.isSuccess, isTrue);
        expect(first.dataOrNull![AssetCatalog.onsAltinId]!.price, 4115.16);

        await provider.waitForPreviousClose();

        // 2. okuma: onceki gunun kapanisi quote'ta.
        final second = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        final q = second.dataOrNull![AssetCatalog.onsAltinId]!;
        expect(q.previousClose, 4140.46);
        expect(q.effectiveChangePercent, isNotNull,
            reason: 'previousClose varsa degisim yuzdesi hesaplanir');
        expect(q.effectiveChangePercent! < 0, isTrue,
            reason: 'fiyat onceki kapanisin altinda');

        // Kapanis istegi DAILY + 40 gunluk pencere + bugunun yarim barini icermez.
        final uri = capturedUri();
        expect(uri.queryParameters['period'], 'DAILY');
        expect(uri.queryParameters['itemDataId'], '12');
        final end = DateTime.parse('${uri.queryParameters['endDate']}Z');
        expect(end.isBefore(DateTime.utc(now.year, now.month, now.day)), isTrue,
            reason: 'bugunun bar\'i previousClose olamaz');
        final start = DateTime.parse('${uri.queryParameters['startDate']}Z');
        expect(
          now.difference(start).inDays,
          CanlidovizProvider.previousCloseWindow.inDays,
          reason: 'pencere 40 gun',
        );
      });

      test('kapanis alinamazsa quote yine de gecerli, degisim UYDURULMAZ',
          () async {
        stubBody('{"data":null,"message":"invalid date range"}', status: 400);

        await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        await provider.waitForPreviousClose();
        // Ikinci ve ucuncu okumada tekrar deneme (istek seli olmaz).
        await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        await provider.fetchQuotes([AssetCatalog.onsAltinId]);

        final q = (await provider.fetchQuotes([AssetCatalog.onsAltinId]))
            .dataOrNull![AssetCatalog.onsAltinId]!;
        expect(q.price, 4115.16, reason: 'fiyat yine de gelir');
        expect(q.previousClose, isNull);
        expect(q.effectiveChangePercent, isNull,
            reason: 'kapanis yoksa yuzde de gosterilmez (sifir/sahte uretilmez)');
        verify(() => mockClient.get(any(), headers: any(named: 'headers')))
            .called(1);
      });

      test('taze tik yoksa kapanis istegi ATILMAZ', () async {
        stream.ticks.clear();
        final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(r.failureOrNull, isA<EmptyFailure>());
        await provider.waitForPreviousClose();
        verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
      });
    });

    group('fetchCandles - desteklenmeyen / gecersiz parametre', () {
      test('cid eslemesi olmayan varlik -> EmptyFailure, istek atilmaz',
          () async {
        final r = await provider.fetchCandles(
          assetId: 'unknown-asset',
          interval: ChartInterval.d1,
        );
        expect(r.failureOrNull, isA<EmptyFailure>());
        verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
      });

      test('limit < 1 -> BadRequestFailure, istek atilmaz', () async {
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.d1,
          limit: 0,
        );
        expect(r.failureOrNull, isA<BadRequestFailure>());
        verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
      });
    });

    group('fetchCandles - basari', () {
      test('m1: OHLC period + itemDataId=12 + tarih bicimi + mumlar', () async {
        stubBody(ohlcBody(count: 5));

        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );

        expect(r.isSuccess, isTrue);
        final series = r.dataOrNull!;
        expect(series.assetId, AssetCatalog.onsAltinId);
        expect(series.interval, ChartInterval.m1);
        expect(series.updatedAt, isNotNull);
        expect(series.candles, hasLength(5));

        // ilk bar alanlari kaynagin aynisi
        final first = series.candles.first;
        expect(first.open, 100);
        expect(first.high, 110);
        expect(first.low, 90);
        expect(first.close, 105);
        expect(first.volume, isNull);

        // URI dogrulamasi
        final uri = capturedUri();
        expect(uri.host, 'a.canlidoviz.com');
        expect(uri.path, '/items/history');
        expect(uri.queryParameters['period'], 'OHLC');
        expect(uri.queryParameters['itemDataId'], '12');

        final re = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$');
        final startRaw = uri.queryParameters['startDate']!;
        final endRaw = uri.queryParameters['endDate']!;
        expect(startRaw, matches(re), reason: 'startDate bicimi');
        expect(endRaw, matches(re), reason: 'endDate bicimi');

        // m1 penceresi = limit * 1 dk
        final diff = DateTime.parse(endRaw).difference(DateTime.parse(startRaw));
        expect(diff, const Duration(minutes: 300));
        // istek su sirada atilmali (endDate ~ simdi, UTC)
        final endUtc = DateTime.parse('${endRaw}Z');
        expect(
          endUtc.difference(DateTime.now().toUtc()).inMinutes.abs(),
          lessThanOrEqualTo(1),
        );
      });

      test('d1: DAILY period + pencere = 300 gun', () async {
        final day = DateTime.utc(2026, 10, 5);
        final dayTs = day.millisecondsSinceEpoch ~/ 1000;
        stubBody('{"$dayTs":"4141.11|4170.72|4123.63|4140.46"}');

        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.d1,
        );

        expect(r.isSuccess, isTrue);
        expect(r.dataOrNull!.candles, hasLength(1));
        expect(r.dataOrNull!.candles.first.close, 4140.46);
        expect(r.dataOrNull!.candles.first.time, day.millisecondsSinceEpoch);

        final uri = capturedUri();
        expect(uri.queryParameters['period'], 'DAILY');
        final diff = DateTime.parse(uri.queryParameters['endDate']!)
            .difference(DateTime.parse(uri.queryParameters['startDate']!));
        expect(diff, const Duration(days: 300));
      });

      test('d1: yeni kapsamda mum-only varlik (14 ayar) cid=16 ile ceker', () async {
        final day = DateTime.utc(2026, 10, 5);
        final dayTs = day.millisecondsSinceEpoch ~/ 1000;
        stubBody('{"$dayTs":"3740|3750|3730|3738.92"}');

        final r = await provider.fetchCandles(
          assetId: AssetCatalog.ayar14AltinId,
          interval: ChartInterval.d1,
        );

        expect(r.isSuccess, isTrue);
        expect(r.dataOrNull!.candles.single.close, 3738.92);
        expect(capturedUri().queryParameters['itemDataId'], '16');
      });

      test('d1: endeks/emtia varliklari kendi cidleriyle ceker', () async {
        final day = DateTime.utc(2026, 10, 5);
        final dayTs = day.millisecondsSinceEpoch ~/ 1000;
        stubBody('{"$dayTs":"11600|11680|11590|11628.07"}');

        expect(
          (await provider.fetchCandles(
            assetId: AssetCatalog.bist50Id,
            interval: ChartInterval.d1,
          )).isSuccess,
          isTrue,
        );
        expect(
          (await provider.fetchCandles(
            assetId: AssetCatalog.dxyId,
            interval: ChartInterval.d1,
          )).isSuccess,
          isTrue,
        );

        final uris = capturedUris();
        expect(uris, hasLength(2));
        expect(uris[0].queryParameters['itemDataId'], '249');
        expect(uris[1].queryParameters['itemDataId'], '846');
        expect(uris[0].queryParameters['period'], 'DAILY');
      });

      test('m5: 1 dk barlar 5 dk kovalarina birlesir', () async {
        stubBody(ohlcBody(count: 10)); // 00:00:59 .. 00:09:59

        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m5,
        );

        expect(r.isSuccess, isTrue);
        final candles = r.dataOrNull!.candles;
        expect(candles, hasLength(2));
        expect(candles[0].open, 100);
        expect(candles[0].close, 109); // 4. barin kapanisi (105+4)
        expect(candles[0].high, 114);
        expect(candles[0].low, 90);
        expect(candles[1].open, 105);
        expect(candles[1].close, 114); // 9. barin kapanisi (105+9)
        expect(candles[0].time, DateTime.utc(2026, 10, 6).millisecondsSinceEpoch);
        expect(capturedUri().queryParameters['period'], 'OHLC');
      });

      test('limit: en fazla istenen kadar mum, en yenisi tutulur', () async {
        stubBody(ohlcBody(count: 5));

        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
          limit: 2,
        );

        expect(r.isSuccess, isTrue);
        final candles = r.dataOrNull!.candles;
        expect(candles, hasLength(2));
        expect(candles.last.close, 109); // son bar
        expect(candles.last.high, 114);
      });

      test('sunucu 200 donup bos obje verdiginde EmptyFailure', () async {
        stubBody('{}');
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<EmptyFailure>());
      });
    });

    group('fetchCandles - hata ayristirma', () {
      test('400 + sunucu mesaji -> BadRequestFailure', () async {
        stubBody('{"data":null,"message":"invalid date range"}', status: 400);
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.d1,
        );
        expect(r.failureOrNull, isA<BadRequestFailure>());
        expect(r.failureOrNull!.message, contains('invalid date range'));
      });

      test('404 -> BadRequestFailure', () async {
        stubBody('not found', status: 404);
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<BadRequestFailure>());
      });

      test('500 -> ServerFailure', () async {
        stubBody('oops', status: 500);
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<ServerFailure>());
      });

      test('bozuk govde (200) -> ParseFailure', () async {
        stubBody('<html>error</html>');
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<ParseFailure>());
      });

      test('ClientException -> NetworkFailure', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenThrow(http.ClientException('connection refused'));
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<NetworkFailure>());
      });

      test('TimeoutException -> TimeoutFailure', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenThrow(TimeoutException('timeout'));
        final r = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
          interval: ChartInterval.m1,
        );
        expect(r.failureOrNull, isA<TimeoutFailure>());
      });
    });

    group('dispose', () {
      test('http client kapatilir', () {
        provider.dispose();
        verify(() => mockClient.close()).called(1);
      });
    });
  });
}
