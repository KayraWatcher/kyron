import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;

import 'package:gold/data/providers/frankfurter_provider.dart';
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

  group('FrankfurterProvider', () {
    late FrankfurterProvider provider;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      provider = FrankfurterProvider(httpClient: mockClient);
    });

    tearDown(() {
      provider.dispose();
    });

    group('supports', () {
      test('returns true for supported FX assets', () {
        expect(provider.supports(AssetCatalog.usdTryId), isTrue);
        expect(provider.supports(AssetCatalog.eurTryId), isTrue);
        expect(provider.supports(AssetCatalog.gbpTryId), isTrue);
        expect(provider.supports(AssetCatalog.chfTryId), isTrue);
        expect(provider.supports(AssetCatalog.jpyTryId), isTrue);
      });

      test('returns false for unsupported assets', () {
        expect(provider.supports(AssetCatalog.gramAltinId), isFalse);
        expect(provider.supports(AssetCatalog.onsAltinId), isFalse);
        expect(provider.supports(AssetCatalog.bist100Id), isFalse);
        expect(provider.supports('unknown-asset'), isFalse);
      });
    });

    group('supportsCandles', () {
      test('returns false for all assets', () {
        expect(provider.supportsCandles(AssetCatalog.usdTryId), isFalse);
        expect(provider.supportsCandles(AssetCatalog.eurTryId), isFalse);
      });
    });

    group('refreshInterval', () {
      test('returns 12 hours', () {
        expect(provider.refreshInterval, const Duration(hours: 12));
      });
    });

    group('id and displayName', () {
      test('id is frankfurter', () {
        expect(provider.id, 'frankfurter');
      });

      test('displayName is Frankfurter (ECB Reference)', () {
        expect(provider.displayName, 'Frankfurter (ECB Reference)');
      });
    });

    group('fetchQuotes', () {
      test('returns empty failure when no supported assets requested', () async {
        final result = await provider.fetchQuotes(['gram-altin', 'ons-altin']);
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<EmptyFailure>());
      });

      test('returns failure when HTTP error', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('Server Error', 500));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('returns failure when empty response', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('', 200));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('returns failure when malformed JSON', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('not valid json', 200));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('returns failure when rates missing', () async {
        final jsonBody = '{"amount":1.0,"base":"USD","date":"2026-10-05"}'; // no rates
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('returns failure when base is not USD', () async {
        final jsonBody = '{"amount":1.0,"base":"EUR","date":"2026-10-05","rates":{"TRY":49.157}}';
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('parses valid response with all supported currencies', () async {
        final jsonBody = '''
        {
          "amount": 1.0,
          "base": "USD",
          "date": "2026-10-05",
          "rates": {
            "TRY": 49.157,
            "EUR": 0.89254,
            "GBP": 0.75616,
            "CHF": 0.83104,
            "JPY": 158.23
          }
        }
        ''';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([
          AssetCatalog.usdTryId,
          AssetCatalog.eurTryId,
          AssetCatalog.gbpTryId,
          AssetCatalog.chfTryId,
          AssetCatalog.jpyTryId,
        ]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull;
        expect(quotes, isNotNull);
        expect(quotes!.length, 5);

        // USD/TRY
        expect(quotes[AssetCatalog.usdTryId]?.price, 49.157);
        expect(quotes[AssetCatalog.usdTryId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.usdTryId]?.freshness, DataFreshness.daily);

        // EUR/TRY (actually USD/EUR from Frankfurter, but asset expects EUR/TRY)
        expect(quotes[AssetCatalog.eurTryId]?.price, 0.89254);
        expect(quotes[AssetCatalog.eurTryId]?.currency, 'TRY');
        expect(quotes[AssetCatalog.eurTryId]?.freshness, DataFreshness.daily);

        // GBP/TRY
        expect(quotes[AssetCatalog.gbpTryId]?.price, 0.75616);
        expect(quotes[AssetCatalog.gbpTryId]?.currency, 'TRY');

        // CHF/TRY
        expect(quotes[AssetCatalog.chfTryId]?.price, 0.83104);
        expect(quotes[AssetCatalog.chfTryId]?.currency, 'TRY');

        // JPY/TRY - Frankfurter returns 1 USD = X JPY (e.g., 158.23)
        // This is NOT per 100 JPY like TCMB
        expect(quotes[AssetCatalog.jpyTryId]?.price, 158.23);
        expect(quotes[AssetCatalog.jpyTryId]?.currency, 'TRY');
      });

      test('handles partial response (some currencies missing)', () async {
        final jsonBody = '''
        {
          "amount": 1.0,
          "base": "USD",
          "date": "2026-10-05",
          "rates": {
            "TRY": 49.157,
            "EUR": 0.89254
          }
        }
        ''';

        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonBody, 200));

        final result = await provider.fetchQuotes([
          AssetCatalog.usdTryId,
          AssetCatalog.eurTryId,
          AssetCatalog.gbpTryId,
        ]);

        expect(result.isSuccess, isTrue);
        final quotes = result.dataOrNull!;
        expect(quotes.length, 2); // Only TRY and EUR present
        expect(quotes[AssetCatalog.usdTryId]?.price, 49.157);
        expect(quotes[AssetCatalog.eurTryId]?.price, 0.89254);
        expect(quotes.containsKey(AssetCatalog.gbpTryId), isFalse);
      });

      test('handles timeout', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(seconds: 20));
          return http.Response('', 200);
        });

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });

      test('handles network error', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenThrow(http.ClientException('Network error'));

        final result = await provider.fetchQuotes([AssetCatalog.usdTryId]);
        expect(result.isFailure, isTrue);
      });
    });

    group('fetchCandles', () {
      test('returns EmptyFailure for all assets', () async {
        final result = await provider.fetchCandles(
          assetId: AssetCatalog.usdTryId,
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