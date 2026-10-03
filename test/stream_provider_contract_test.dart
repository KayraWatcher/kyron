// GOLD v2 - Akis (stream) sozlesme testi.
//
// Amaç: kaynak secilmeden **hicbir** saglayicinin "gercek zamanli / canli"
// iddiasi olamaz. Bu test, arayuzun disaridan "sonradan eklenebilecek" bicimde
// hazir oldugunu ve uygulamanin **gercekten kullandigi kaynak listesinde**
// akis iddiasi bulunmadigini dogrular.
//
//  * Yahoo REST -> periyodik HTTP sorgusu; akis DEGIL.
//  * TCMB       -> gunluk resmi kur; akis DEGIL.
//  Bu ikisi `StreamableMarketDataProvider` DEGILDIR ve `DataFreshness.live`
//  uretemez.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:gold/domain/providers/stream_market_data_provider.dart';

/// Kaynak secildiginde eklenecek **ornek** saglayicinin sozlesmeye tam
/// uygulandigini dogrulamak icin minimal yer tutucu.
class _StreamSource implements StreamableMarketDataProvider {
  @override
  String get id => 'ornek-akis';

  @override
  String get displayName => 'Örnek Akış';

  @override
  String get streamProtocol => 'WebSocket';

  @override
  Duration get streamLatency => Duration.zero;

  @override
  bool get streamRequiresApiKey => false;

  @override
  Duration get refreshInterval => const Duration(seconds: 1);

  @override
  bool supports(String assetId) => true;

  @override
  bool supportsStreaming(String assetId) => true;

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async =>
      const Success({});

  @override
  Stream<Result<Map<String, Quote>>> watchQuotes(List<String> assetIds) =>
      const Stream<Success<Map<String, Quote>>>.empty();

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err<CandleSeries>(EmptyFailure('mum yok'));
}

void main() {
  group('Akis sözlesmesi', () {
    late ProviderContainer c;

    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('yeni kaynak arayuzu tam uygulayabilir (sonradan eklenebilir)', () {
      final source = _StreamSource();

      expect(source, isA<StreamableMarketDataProvider>());
      // Mevcut mimari korunur: hala normal bir saglayicidir.
      expect(source, isA<MarketDataProvider>());
      expect(source.supportsStreaming('bist100'), isTrue);
      expect(source.streamProtocol, isNotEmpty);
      expect(source.streamRequiresApiKey, isFalse);
      expect(source.streamLatency, Duration.zero);
    });

    test('uygulamanin GERCEK kaynak listesinde akis iddiasi yok', () {
      final sources = c.read(marketSourcesProvider);

      expect(sources, isNotEmpty);
      for (final s in sources) {
        expect(
          s,
          isNot(isA<StreamableMarketDataProvider>()),
          reason:
              '${s.id} akis (stream) sagladigini iddia ediyor; "Canlı" '
              'etiketi yalnizca gercekten dogrulanan akis kaynagindan gelir.',
        );
      }
    });
  });
}
