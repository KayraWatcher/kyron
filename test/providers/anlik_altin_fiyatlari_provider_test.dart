import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;

import 'package:gold/data/providers/anlik_altin_fiyatlari_provider.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/core/error/failures.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(<String, String>{});
  });

  group('AnlikAltinFiyatlariProvider', () {
    late AnlikAltinFiyatlariProvider provider;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      provider = AnlikAltinFiyatlariProvider(httpClient: mockClient);
    });

    tearDown(() {
      provider.dispose();
    });

    group('supports', () {
      test('returns true for supported gold assets', () {
        expect(provider.supports(AssetCatalog.gramAltinId), isTrue);
        expect(provider.supports(AssetCatalog.ceyrekAltinId), isTrue);
        expect(provider.supports(AssetCatalog.yarimAltinId), isTrue);
        expect(provider.supports(AssetCatalog.cumhuriyetAltinId), isTrue);
        expect(provider.supports(AssetCatalog.bilezik22Id), isTrue);
        // New products with verified live endpoints
        expect(provider.supports(AssetCatalog.ayar14AltinId), isTrue);
        expect(provider.supports(AssetCatalog.ayar18AltinId), isTrue);
        expect(provider.supports(AssetCatalog.resatAltinId), isTrue);
        // Silver products
        expect(provider.supports(AssetCatalog.gramGumusId), isTrue);
        expect(provider.supports(AssetCatalog.onsGumusId), isTrue);
      });

      test('returns false for unsupported assets', () {
        expect(provider.supports(AssetCatalog.usdTryId), isFalse);
        expect(provider.supports(AssetCatalog.eurTryId), isFalse);
        expect(provider.supports(AssetCatalog.bist100Id), isFalse);
        expect(provider.supports('unknown-asset'), isFalse);
      });

      test('returns false for calculated assets without live endpoint', () {
        // Yarim altin is calculated but has live endpoint
        expect(provider.supports(AssetCatalog.yarimAltinId), isTrue);
        // Tam altin calculated but no confirmed live endpoint
        expect(provider.supports(AssetCatalog.tamAltinId), isFalse);
        expect(provider.supports(AssetCatalog.ataAltinId), isFalse);
      });
    });

    group('supportsCandles', () {
      test('returns false for all assets', () {
        expect(provider.supportsCandles(AssetCatalog.gramAltinId), isFalse);
        expect(provider.supportsCandles(AssetCatalog.ceyrekAltinId), isFalse);
      });
    });

    group('refreshInterval', () {
      test('returns 60 seconds', () {
        expect(provider.refreshInterval, const Duration(seconds: 60));
      });
    });

    group('id and displayName', () {
      test('id is anlikaltinfiyatlari', () {
        expect(provider.id, 'anlikaltinfiyatlari');
      });

      test('displayName is Anlık Altın Fiyatları', () {
        expect(provider.displayName, 'Anlık Altın Fiyatları');
      });
    });

    group('fetchQuotes', () {
      test('returns empty failure when no supported assets requested', () async {
        final result = await provider.fetchQuotes(['usd-try', 'eur-try']);
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<EmptyFailure>());
      });

      test('returns empty failure when no valid responses', () async {
        // Mock client returns 404
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('Not Found', 404));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('parses valid response correctly', () async {
        // Use recent timestamps (within 2 minutes of now) for live freshness
        final now = DateTime.now();
        final recentTimestamp = now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch;

        final mockData = [
          [recentTimestamp - 60000, 6538.9492],
          [recentTimestamp, 6546.6014],
        ];
        final jsonBody = '[${mockData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull;
        expect(quotes, isNotNull);
        expect(quotes!.containsKey(AssetCatalog.gramAltinId), isTrue);

        final quote = quotes[AssetCatalog.gramAltinId]!;
        expect(quote.assetId, AssetCatalog.gramAltinId);
        expect(quote.price, 6546.6014); // Last price in array
        expect(quote.source, QuoteSourceLabel.market);
        expect(quote.currency, 'TRY');
        expect(quote.price, isNotNull);
        // Test freshness is live for fresh data (within 2 minutes)
        expect(quote.freshness, DataFreshness.live);
      });

      test('handles malformed JSON gracefully', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('not valid json', 200));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles empty response gracefully', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('[]', 200));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles HTTP error status', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('Server Error', 500));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles timeout', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(seconds: 15));
          return http.Response('', 200);
        });

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles empty response', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('', 200));

        final result = await provider.fetchQuotes([AssetCatalog.gramAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles multiple assets in single call', () async {
        // Use recent timestamps
        final now = DateTime.now();
        final recentTimestamp = now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch;

        final gramData = [
          [recentTimestamp - 60000, 6538.9492],
          [recentTimestamp, 6546.6014],
        ];
        final ceyrekData = [
          [recentTimestamp - 60000, 10854.6557],
          [recentTimestamp, 10867.3583],
        ];

        final gramResponse = '[${gramData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';
        final ceyrekResponse = '[${ceyrekData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((invocation) {
          final uri = invocation.positionalArguments.first as Uri;
          final filename = uri.queryParameters['filename'];
          if (filename == 'gramlive.json') return Future.value(http.Response(gramResponse, 200));
          if (filename == 'ceyreklive.json') return Future.value(http.Response(ceyrekResponse, 200));
          return Future.value(http.Response('[]', 200));
        });

        final result = await provider.fetchQuotes([
          AssetCatalog.gramAltinId,
          AssetCatalog.ceyrekAltinId,
        ]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull!;
        expect(quotes.length, 2);
        expect(quotes[AssetCatalog.gramAltinId]?.price, 6546.6014);
        expect(quotes[AssetCatalog.ceyrekAltinId]?.price, 10867.3583);
        // Both should have live freshness
        expect(quotes[AssetCatalog.gramAltinId]?.freshness, DataFreshness.live);
        expect(quotes[AssetCatalog.ceyrekAltinId]?.freshness, DataFreshness.live);
      });

      test('parses new products (14 Ayar, 18 Ayar, Reşat, Ons Gümüş, Gram Gümüş) correctly', () async {
        final now = DateTime.now();
        final recentTimestamp = now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch;

        // Mock data for each new product based on real endpoint responses
        final ayar14Data = [
          [recentTimestamp - 60000, 3857.98],
          [recentTimestamp, 3862.4948],
        ];
        final ayar18Data = [
          [recentTimestamp - 60000, 4963.0624],
          [recentTimestamp, 4968.8705],
        ];
        final resatData = [
          [recentTimestamp - 60000, 44661.023],
          [recentTimestamp, 44713.2876],
        ];
        final onsGumusData = [
          [recentTimestamp - 60000, 60.3725],
          [recentTimestamp, 60.397],
        ];
        final gramGumusData = [
          [recentTimestamp - 60000, 95.3944],
          [recentTimestamp, 95.3944],
        ];

        final ayar14Response = '[${ayar14Data.map((e) => '[${e[0]},${e[1]}]').join(',')}]';
        final ayar18Response = '[${ayar18Data.map((e) => '[${e[0]},${e[1]}]').join(',')}]';
        final resatResponse = '[${resatData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';
        final onsGumusResponse = '[${onsGumusData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';
        final gramGumusResponse = '[${gramGumusData.map((e) => '[${e[0]},${e[1]}]').join(',')}]';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((invocation) {
          final uri = invocation.positionalArguments.first as Uri;
          final filename = uri.queryParameters['filename'];
          if (filename == '14ayarlive.json') return Future.value(http.Response(ayar14Response, 200));
          if (filename == '18ayarlive.json') return Future.value(http.Response(ayar18Response, 200));
          if (filename == 'resatlive.json') return Future.value(http.Response(resatResponse, 200));
          if (filename == 'gumusonslive.json') return Future.value(http.Response(onsGumusResponse, 200));
          if (filename == 'gumuslive.json') return Future.value(http.Response(gramGumusResponse, 200));
          return Future.value(http.Response('[]', 200));
        });

        final result = await provider.fetchQuotes([
          AssetCatalog.ayar14AltinId,
          AssetCatalog.ayar18AltinId,
          AssetCatalog.resatAltinId,
          AssetCatalog.onsGumusId,
          AssetCatalog.gramGumusId,
        ]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull!;
        expect(quotes.length, 5);

        // 14 Ayar - TRY/gram
        expect(quotes[AssetCatalog.ayar14AltinId]?.price, 3862.4948);
        expect(quotes[AssetCatalog.ayar14AltinId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.ayar14AltinId]?.freshness, DataFreshness.live);

        // 18 Ayar - TRY/gram
        expect(quotes[AssetCatalog.ayar18AltinId]?.price, 4968.8705);
        expect(quotes[AssetCatalog.ayar18AltinId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.ayar18AltinId]?.freshness, DataFreshness.live);

        // Reşat - TRY/gram (but represents 7.216g unit)
        expect(quotes[AssetCatalog.resatAltinId]?.price, 44713.2876);
        expect(quotes[AssetCatalog.resatAltinId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.resatAltinId]?.freshness, DataFreshness.live);

        // Ons Gümüş - USD/ons
        expect(quotes[AssetCatalog.onsGumusId]?.price, 60.397);
        expect(quotes[AssetCatalog.onsGumusId]?.currency, 'USD');
        expect(quotes[AssetCatalog.onsGumusId]?.freshness, DataFreshness.live);

        // Gram Gümüş - TRY/gram
        expect(quotes[AssetCatalog.gramGumusId]?.price, 95.3944);
        expect(quotes[AssetCatalog.gramGumusId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.gramGumusId]?.freshness, DataFreshness.live);
      });
    });

    group('fetchCandles', () {
      test('returns EmptyFailure for all assets', () async {
        final result = await provider.fetchCandles(
          assetId: AssetCatalog.gramAltinId,
          interval: ChartInterval.d1,
        );
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<EmptyFailure>());
      });
    });

    group('dispose', () {
      test('closes http client', () {
        provider.dispose();
        verify(() => mockClient.close()).called(1);
      });
    });
  });
}