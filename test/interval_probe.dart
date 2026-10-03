// Faz E dogrulamasi: Yahoo GERCEKTEN hangi zaman dilimlerini destekliyor?
//
// Bu dosya bilerek `*_test.dart` **adlandirilmadi**; `flutter test` (ag
// gerektirmeyen kapi) etkilenmez.
//
// Calistirmak icin:
//     flutter test test/interval_probe.dart
//
// Amaç: "4 saat" gibi bir dilimi UI'da gostermeden once, saglayicinin o
// dilimde **gerçekten** mum dondurup dondurmedigini ve donen mumlarin
// araliginin istenen aralikla **eslesip eslesmedigini** olcmek. Sonuc
// `MarketDataProvider.supportedIntervals` icine yazilir; UI yalnizca o
// kumesi gosterir (uydurma dilim yok).
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/domain/entities/candle.dart';

void main() {
  test('interval destek taramasi', () async {
    final client = ApiClient();
    final yahoo = YahooFinanceProvider(client);

    const symbols = <String>['XU100.IS', 'GC=F', 'USDTRY=X'];
    final rows = <String>[];

    for (final symbol in symbols) {
      for (final iv in ChartInterval.values) {
        final res = await yahoo
            .fetchCandles(symbol: symbol, interval: iv, limit: 200)
            .timeout(const Duration(seconds: 30));

        final series = res.dataOrNull;
        if (series == null || series.candles.length < 2) {
          rows.add('$symbol ${iv.name} (${iv.label}) -> YOK '
              '${res.failureOrNull ?? ''}');
          continue;
        }

        final c = series.candles;
        // Aralik olcumu: ardisan mumlarin zaman farklarinin medyani.
        final deltas = <int>[];
        for (var i = 1; i < c.length; i++) {
          deltas.add(c[i].time - c[i - 1].time);
        }
        deltas.sort();
        final median = deltas[deltas.length ~/ 2];
        final expected = iv.duration.inMilliseconds;
        final ratio = (median / expected * 100).toStringAsFixed(0);

        rows.add('$symbol ${iv.name} (${iv.label}) -> ${c.length} mum, '
            'medyan aralik ${median ~/ 1000}s, istenen '
            '${expected ~/ 1000}s, oran %$ratio');
      }
    }

    // ignore: avoid_print
    print('\n=== INTERVAL TARAMASI ===\n${rows.join('\n')}\n========================');

    // En az bir symbol'de anlamli veri donmeli (ag varsa).
    expect(rows.where((r) => r.contains('mum,')).isNotEmpty, isTrue,
        reason: 'hicbir aralikta mum gelmedi - ag/istemci hatasi');
  });
}
