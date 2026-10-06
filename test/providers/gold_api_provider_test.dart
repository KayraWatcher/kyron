import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;

import 'package:gold/data/providers/gold_api_provider.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/core/error/failures.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(<String, String>{});
  });

  group('GoldApiProvider', () {
    late GoldApiProvider provider;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      provider = GoldApiProvider(httpClient: mockClient);
    });

    tearDown(() {
      provider.dispose();
    });

    group('supports', () {
      test('returns true for XAU (ons altin)', () {
        expect(provider.supports(AssetCatalog.onsAltinId), isTrue);
      });

      test('returns true for XAG (ons gumus)', () {
        expect(provider.supports(AssetCatalog.onsGumusId), isTrue);
      });

      test('returns false for unsupported assets', () {
        expect(provider.supports(AssetCatalog.gramAltinId), isFalse);
        expect(provider.supports(AssetCatalog.usdTryId), isFalse);
        expect(provider.supports(AssetCatalog.bist100Id), isFalse);
        expect(provider.supports('unknown-asset'), isFalse);
      });
    });

    group('supportsCandles', () {
      test('returns false for all assets', () {
        expect(provider.supportsCandles(AssetCatalog.onsAltinId), isFalse);
        expect(provider.supportsCandles(AssetCatalog.onsGumusId), isFalse);
      });
    });

    group('refreshInterval', () {
      test('returns 60 seconds', () {
        expect(provider.refreshInterval, const Duration(seconds: 60));
      });
    });

    group('id and displayName', () {
      test('id is gold-api', () {
        expect(provider.id, 'gold-api');
      });

      test('displayName is Gold API (Spot)', () {
        expect(provider.displayName, 'Gold API (Spot)');
      });
    });

    group('fetchQuotes', () {
      test('returns empty failure when no supported assets requested', () async {
        final result = await provider.fetchQuotes(['usd-try', 'eur-try']);
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<EmptyFailure>());
      });

      test('returns empty failure when HTTP error', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('Server Error', 500));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('returns empty failure when empty response', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('', 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('returns empty failure when malformed JSON', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('not valid json', 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('returns empty failure when price missing', () async {
        final jsonBody = '{"symbol":"XAU","name":"Gold"}'; // no price
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('parses valid XAU response correctly', () async {
        final now = DateTime.now().toUtc().toIso8601String();
        final jsonBody = '{"symbol":"XAU","name":"Gold","price":4141.5,"currency":"USD","updatedAt":"$now"}';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull;
        expect(quotes, isNotNull);
        expect(quotes!.containsKey(AssetCatalog.onsAltinId), isTrue);

        final quote = quotes[AssetCatalog.onsAltinId]!;
        expect(quote.assetId, AssetCatalog.onsAltinId);
        expect(quote.price, 4141.5);
        expect(quote.source, QuoteSourceLabel.market);
        expect(quote.currency, 'USD');
        expect(quote.freshness, DataFreshness.live);
      });

      test('parses valid XAG response correctly', () async {
        final now = DateTime.now().toUtc().toIso8601String();
        final jsonBody = '{"symbol":"XAG","name":"Silver","price":61.19,"currency":"USD","updatedAt":"$now"}';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsGumusId]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull;
        expect(quotes, isNotNull);
        expect(quotes!.containsKey(AssetCatalog.onsGumusId), isTrue);

        final quote = quotes[AssetCatalog.onsGumusId]!;
        expect(quote.assetId, AssetCatalog.onsGumusId);
        expect(quote.price, 61.19);
        expect(quote.source, QuoteSourceLabel.market);
        expect(quote.currency, 'USD');
        expect(quote.freshness, DataFreshness.live);
      });

      test('handles both XAU and XAG in single call', () async {
        final now = DateTime.now().toUtc().toIso8601String();
        final xauBody = '{"symbol":"XAU","name":"Gold","price":4141.5,"currency":"USD","updatedAt":"$now"}';
        final xagBody = '{"symbol":"XAG","name":"Silver","price":61.19,"currency":"USD","updatedAt":"$now"}';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((invocation) {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path.endsWith('/XAU')) return Future.value(http.Response(xauBody, 200));
          if (uri.path.endsWith('/XAG')) return Future.value(http.Response(xagBody, 200));
          return Future.value(http.Response('{}', 200));
        });

        final result = await provider.fetchQuotes([
          AssetCatalog.onsAltinId,
          AssetCatalog.onsGumusId,
        ]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull!;
        expect(quotes.length, 2);
        expect(quotes[AssetCatalog.onsAltinId]?.price, 4141.5);
        expect(quotes[AssetCatalog.onsGumusId]?.price, 61.19);
        expect(quotes[AssetCatalog.onsAltinId]?.freshness, DataFreshness.live);
        expect(quotes[AssetCatalog.onsGumusId]?.freshness, DataFreshness.live);
      });

      test('handles timeout', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(seconds: 15));
          return http.Response('', 200);
        });

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
        expect(result.isFailure, isTrue);
      });

      test('handles stale timestamp (older than 2 minutes) -> delayed freshness', () async {
        final staleTime = DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String();
        final jsonBody = '{"symbol":"XAU","name":"Gold","price":4141.5,"currency":"USD","updatedAt":"$staleTime"}';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);

        expect(result.isSuccess, isTrue);
        final quote = result.dataOrNull![AssetCatalog.onsAltinId]!;
        expect(quote.freshness, DataFreshness.delayed);
      });

      test('handles very old timestamp (older than 5 minutes) -> daily freshness', () async {
        final oldTime = DateTime.now().subtract(const Duration(minutes: 10)).toUtc().toIso8601String();
        final jsonBody = '{"symbol":"XAU","name":"Gold","price":4141.5,"currency":"USD","updatedAt":"$oldTime"}';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.onsAltinId]);

        expect(result.isSuccess, isTrue);
        final quote = result.dataOrNull![AssetCatalog.onsAltinId]!;
        expect(quote.freshness, DataFreshness.daily);
      });
    });

    group('fetchCandles', () {
      test('returns EmptyFailure for all assets', () async {
        final result = await provider.fetchCandles(
          assetId: AssetCatalog.onsAltinId,
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