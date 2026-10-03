// Regresyon testi - zaman dilimi degisimi + provider yazimi.
//
// Cihaz testinde (2026-10-03, Xiaomi 2201116TG) "1 sa" chip'ine basildiginda
// ekran kirmizi hata widget'i ile degismisti:
//   "Tried to modify a provider while the widget tree was building."
//
// Kok nedir: `_ChartSection.didUpdateWidget` icinde `crosshairCandleProvider`
// yaziliyordu. Widget yasam dongusu (didUpdateWidget) build asamasidir ve
// Riverpod bu asamada provider degistirmeyi hata sayar.
// Duzeltme: yazim, dilimin degistigi tek olay baglamina tasindi
// (`_IntervalBar.onChanged`); `didUpdateWidget` artik yalnizca yerel durumu
// sifirlar.
//
// Bu test iki davranisi korur:
//  1. Dilim chip'ine basinca hata uretilmemeli (regresyon).
//  2. Secili imlec mumu dilim degisince temizlenmeli (davranis korunur).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold/core/error/failures.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:gold/features/asset_detail/asset_detail_providers.dart';
import 'package:gold/features/asset_detail/asset_detail_screen.dart';
import 'package:gold/features/charts/interactive_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSource implements MarketDataProvider {
  const FakeSource();

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  Duration get refreshInterval => const Duration(seconds: 1);

  @override
  bool supports(String assetId) => true;

  @override
  bool supportsCandles(String assetId) => true;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final now = DateTime.now();
    return Success({
      for (final id in assetIds)
        id: Quote(
          assetId: id,
          source: QuoteSourceLabel.market,
          updatedAt: now,
          price: 4100,
          previousClose: 4080,
          currency: 'USD',
          freshness: DataFreshness.daily,
        ),
    });
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
    return Success(
      CandleSeries(
        assetId: assetId,
        interval: interval,
        candles: [
          for (var i = 0; i < limit; i++)
            Candle(
              time: base + i * 86400000,
              open: 2000 + (i % 50) * 3.0,
              high: 2012 + (i % 50) * 3.0,
              low: 1992 + (i % 50) * 3.0,
              close: 2006 + (i % 50) * 3.0,
              volume: 1000 + i * 10.0,
            ),
        ],
      ),
    );
  }
}

const String assetId = 'ons-altin';

Future<ProviderContainer> _boot(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        marketSourcesProvider.overrideWithValue(const [FakeSource()]),
      ],
      child: const MaterialApp(home: AssetDetailScreen(assetId: assetId)),
    ),
  );

  for (var i = 0; i < 40 && find.byType(InteractiveChart).evaluate().isEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(InteractiveChart), findsOneWidget,
      reason: 'grafik yuklenmeli');
  // initState'teki gosterge mikro gorevi + ilk render.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));

  return ProviderScope.containerOf(
    tester.element(find.byType(AssetDetailScreen)),
  );
}

void main() {
  testWidgets('dilim chipine basinca provider-yazim hatasi cikmaz (regresyon)',
      (tester) async {
    await _boot(tester);

    // Varsayilan dilim '1 gün' (ChartInterval.d1).
    final defaultChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1 gün'),
    );
    expect(defaultChip.selected, isTrue);

    // Cihazda hatayi tetikleyen hareket: baska bir dilim sec.
    await tester.tap(find.widgetWithText(ChoiceChip, '1 dk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final exception = tester.takeException();
    expect(exception, isNull,
        reason: 'dilim degisimi provider yazim hatasi uretmemeli: $exception');

    // Secim gercekten uygulanmali.
    final m1Chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1 dk'),
    );
    expect(m1Chip.selected, isTrue, reason: '1 dk secili olmali');
    expect(find.byType(InteractiveChart), findsOneWidget);

    // Ikinci dilim degisimi de hatasiz (ust üste yazimlar).
    await tester.tap(find.widgetWithText(ChoiceChip, '4 sa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final second = tester.takeException();
    expect(second, isNull, reason: 'ikinci dilim degisiminde hata: $second');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dilim degisince secili imlec mumu temizlenir', (tester) async {
    final container = await _boot(tester);

    // Imlec mumi elle isaretle (kullanici cekmeden mantigi dogrulamak icin).
    container.read(crosshairCandleProvider(assetId).notifier).pick(
          const Candle(
            time: 1704067200000,
            open: 10,
            high: 12,
            low: 9,
            close: 11,
            volume: 100,
          ),
        );
    expect(container.read(crosshairCandleProvider(assetId)), isNotNull);

    await tester.tap(find.widgetWithText(ChoiceChip, '5 dk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(crosshairCandleProvider(assetId)), isNull,
        reason: 'yeni dilimde eski imlec mumu anlamsizdir - temizlenmeli');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
