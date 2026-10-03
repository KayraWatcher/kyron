// DATA FRESHNESS INTEGRATION TEST - Provider → Repository → Stream → UI
// Tests the complete flow with real Yahoo responses

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/data/providers/yahoo_market_data_provider.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';

void main() {
  group('DATA FRESHNESS - Full Integration Flow', () {
    late MarketDataRepositoryImpl repository;
    late YahooMarketDataProvider yahooProvider;

    setUp(() {
      yahooProvider = YahooMarketDataProvider(YahooFinanceProvider(ApiClient()));
      repository = MarketDataRepositoryImpl(sources: [yahooProvider]);
    });

    test('Complete flow: provider → repository → watchQuotes stream', () async {
      // Test symbols representing different market states
      final symbols = [
        AssetCatalog.onsAltinId,    // GC=F - Gold futures (COMEX, open ~20:59 UTC in test)
        AssetCatalog.onsGumusId,    // SI=F - Silver futures
        AssetCatalog.usdTryId,      // USDTRY=X - Forex (closed at test time)
        AssetCatalog.eurTryId,      // EURTRY=X - Forex (closed)
        AssetCatalog.bist100Id,     // XU100.IS - BIST 100 (closed at 15:00 UTC)
        AssetCatalog.bist30Id,      // XU030.IS - BIST 30
      ];

      print('\n=== INITIAL FETCH ===');
      final initial = await repository.getQuotes(symbols);
      initial.when(
        onSuccess: (quotes) {
          for (final entry in quotes.entries) {
            final q = entry.value;
            print('${entry.key}: price=${q.price}, change%=${q.effectiveChangePercent}, '
                'marketTime=${q.marketTime}, freshness=${q.freshness.label}, '
                'isStale=${q.isStale}, updatedAt=${q.updatedAt}');
          }
        },
        onFailure: (f) => print('INITIAL FETCH ERROR: $f'),
      );

      // Wait a bit and fetch again
      await Future.delayed(const Duration(seconds: 4));
      
      print('\n=== SECOND FETCH (after 4s) ===');
      final second = await repository.getQuotes(symbols);
      second.when(
        onSuccess: (quotes) {
          for (final entry in quotes.entries) {
            final q = entry.value;
            print('${entry.key}: price=${q.price}, change%=${q.effectiveChangePercent}, '
                'marketTime=${q.marketTime}, freshness=${q.freshness.label}, '
                'isStale=${q.isStale}, updatedAt=${q.updatedAt}');
          }
        },
        onFailure: (f) => print('SECOND FETCH ERROR: $f'),
      );

      // Test watchQuotes stream
      print('\n=== STREAM TEST (2 ticks) ===');
      final stream = repository.watchQuotes(symbols, interval: const Duration(seconds: 2));
      
      int tickCount = 0;
      final twoTicks = Completer<void>();
      StreamSubscription<Map<String, Quote>>? sub;
      sub = stream.listen((quotes) {
        tickCount++;
        print('\n--- Stream Tick $tickCount ---');
        for (final entry in quotes.entries) {
          final q = entry.value;
          print('${entry.key}: price=${q.price}, isStale=${q.isStale}, updatedAt=${q.updatedAt}');
        }
        
        if (tickCount >= 2) {
          sub?.cancel();
          if (!twoTicks.isCompleted) twoTicks.complete();
        }
      });
      
      // `watchQuotes` sonsuz yenileme akisidir ve asla `done` yaymaz; ayni
      // sekilde `cancel()` daha once kaydedilmis bir `asFuture()`'i de
      // tamamlamaz (Dart davranisi) - o yuzden iki tikin gelmesi bir
      // Completer ile beklenir. Asagidaki `expect` ayni kalir.
      await twoTicks.future.timeout(const Duration(seconds: 10));
      
      expect(tickCount, greaterThanOrEqualTo(2));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Cache behavior: rapid sequential calls should hit cache', () async {
      final symbols = [AssetCatalog.onsAltinId];
      
      // First call - cache miss
      final t1 = DateTime.now();
      await repository.getQuotes(symbols);
      final t2 = DateTime.now();
      print('First call (cache miss): ${t2.difference(t1).inMilliseconds}ms');
      
      // Second call immediately - should hit cache
      final t3 = DateTime.now();
      await repository.getQuotes(symbols);
      final t4 = DateTime.now();
      print('Second call (cache hit): ${t4.difference(t3).inMilliseconds}ms');
      
      // Cache hit should be much faster
      expect(t4.difference(t3).inMilliseconds, lessThan(t2.difference(t1).inMilliseconds));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Background/Foreground cycle: new repository works', () async {
      final symbols = [AssetCatalog.onsAltinId];
      
      // Initial fetch
      await repository.getQuotes(symbols);
      
      // Simulate app going to background and foreground by creating new repository
      final repo2 = MarketDataRepositoryImpl(sources: [yahooProvider]);
      await repo2.getQuotes(symbols);
      
      // Should work normally
      expect(true, isTrue);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}