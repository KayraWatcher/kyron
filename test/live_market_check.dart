// LIVE MARKET CHECK - Gerçek cihazda Yahoo Finance response'larını yakalamak için
// flutter test test/live_market_check.dart -d <device_id> --plain-name "live"

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/core/network/api_client.dart';

void main() {
  group('LIVE MARKET CHECK - Gerçek Yahoo Response', () {
    late YahooFinanceProvider provider;

    setUp(() {
      provider = YahooFinanceProvider(ApiClient());
    });

    // Test: Gerçek sembolleri çek ve RAW response logla
    test('GC=F, SI=F, USDTRY=X, EURTRY=X, XU100.IS, THYAO.IS - RAW response', () async {
      final symbols = [
        'GC=F',      // Ons Altın
        'SI=F',      // Ons Gümüş
        'USDTRY=X',  // USD/TRY
        'EURTRY=X',  // EUR/TRY
        'XU100.IS',  // BIST 100
        'THYAO.IS',  // THY
      ];

      for (final symbol in symbols) {
        print('\n===== $symbol =====');
        
        // Ham HTTP response al
        final uri = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=5d&includePrePost=false');
        final client = http.Client();
        
        try {
          final requestStart = DateTime.now().toUtc();
          final response = await client.get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
            },
          ).timeout(const Duration(seconds: 15));
          final requestEnd = DateTime.now().toUtc();
          
          print('HTTP Status: ${response.statusCode}');
          print('Content-Type: ${response.headers['content-type']}');
          print('Content-Length: ${response.headers['content-length']}');
          print('Date Header: ${response.headers['date']}');
          print('Request Duration: ${requestEnd.difference(requestStart).inMilliseconds}ms');
          print('Request Time (UTC): $requestStart');
          
          if (response.statusCode == 200) {
            // RAW body bytes
            print('Body Length: ${response.bodyBytes.length} bytes');
            
            // İlk 500 char
            final preview = response.body.length > 500 
                ? response.body.substring(0, 500) 
                : response.body;
            print('Body Preview: $preview');
            
            // Parse meta using provider
            final metaResult = await provider.fetchQuote(symbol);
            metaResult.when(
              onSuccess: (meta) {
                print('\n--- PARSED META ---');
                print('symbol: ${meta.symbol}');
                print('currency: ${meta.currency}');
                print('price: ${meta.price}');
                print('previousClose: ${meta.previousClose}');
                print('chartPreviousClose: ${meta.chartPreviousClose}');
                print('change: ${meta.change}');
                print('changePercent: ${meta.changePercent}');
                print('dayHigh: ${meta.dayHigh}');
                print('dayLow: ${meta.dayLow}');
                print('volume: ${meta.volume}');
                print('marketTime: ${meta.marketTime}');
                print('isRegularMarketTime: ${meta.isRegularMarketTime}');
                print('regularMarketStart: ${meta.regularMarketStart}');
                print('regularMarketEnd: ${meta.regularMarketEnd}');
                print('hasTradingSession: ${meta.hasTradingSession}');
                final nowUtc = DateTime.now().toUtc();
                print('freshness (calculated): ${meta.hasTradingSession ? (meta.isMarketOpenAt(nowUtc) ? 'delayed' : 'closed') : 'unknown'}');
                print('effectivePreviousClose: ${meta.effectivePreviousClose}');
                print('effectiveChange: ${meta.effectiveChange}');
                print('effectiveChangePercent: ${meta.effectiveChangePercent}');
              },
              onFailure: (f) {
                print('PARSE ERROR: $f');
              },
            );
          } else {
            print('HTTP ERROR: ${response.statusCode}');
            print('Body: ${response.body}');
          }
        } catch (e, st) {
          print('EXCEPTION: $e');
          print(st);
        } finally {
          client.close();
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    // Test: fetchQuotes kullanarak aynı sembolleri çek
    test('fetchQuotes batch test', () async {
      final symbols = ['GC=F', 'SI=F', 'USDTRY=X', 'EURTRY=X', 'XU100.IS', 'THYAO.IS'];
      
      final start = DateTime.now().toUtc();
      final result = await provider.fetchQuotes(symbols);
      final end = DateTime.now().toUtc();
      
      print('\n===== fetchQuotes BATCH =====');
      print('Duration: ${end.difference(start).inMilliseconds}ms');
      
      result.when(
        onSuccess: (metas) {
          for (final entry in metas.entries) {
            final meta = entry.value;
            print('\n--- ${entry.key} ---');
            print('price: ${meta.price}');
            print('change: ${meta.effectiveChange}');
            print('change%: ${meta.effectiveChangePercent}');
            print('marketTime: ${meta.marketTime}');
            final nowUtc = DateTime.now().toUtc();
            print('freshness: ${meta.hasTradingSession ? (meta.isMarketOpenAt(nowUtc) ? 'delayed' : 'closed') : 'unknown'}');
          }
        },
        onFailure: (f) {
          print('ERROR: $f');
        },
      );
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}