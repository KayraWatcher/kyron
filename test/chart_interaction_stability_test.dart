// Regresyon testi - grafik etkilesim kararliligi (cihaz kok nedeni).
//
// Cihaz testinde (2026-10-03, Xiaomi 2201116TG, release APK) kullanici
// "grafiye dokunuyorum ve hicbir tepki yok" bildiriyordu. Repro adimlari:
//  * Uzun basma imleci ACIYOR ama yatay cizgi + fiyat etiketi parmagin
//    ~230px ustunde ciziliyordu (hareketsiz basili tutmada olculdu:
//    drawbox isareti ile dokunma noktasi birebir karsilastirildi).
//  * Grafin ust kismina (ilk ~230px) basildiginda cizgi grafik alanindan
//    disari tasiyordu -> ekranda hicbir sey gorunmez, kullanici icin
//    tamamen "tepki yok".
//  * Imlec kapandiginda grafik alani ~230px geri kayiyor (ziplama).
//
// KOK NEDEN: `_Header` canli icerik (`_headerData`) ile imlec icerigi
// (`_headerPicked`) arasinda yukseklik degistiriyordu; imlec acilinca
// baslik kisalir, Column'daki grafik alani yukari kayar, imlecin
// saklanan yerel Y degeri gecersizlesirdi.
//
// Duzeltme: imlec modunda canli icerik ayni kutuda gorunmez yer tutar;
// baslik yuksekligi mod gecislerinde sabit kalir.
//
// Bu testler duzeltme sonrasi davranisi kilitler:
//  1. Imlec acilirken/kapanirken InteractiveChart ust konumu DEGMEZ.
//  2. Imlec acikken ust baslik "Gecmis mum" gosterir (ozellik korunur).
//  3. Imlec kapandiktan sonra canli metinler geri doner.
//  4. Hizli dilim degisimlerinden sonra imlec hala calisir.
//  5. Dar ekranda (360x640) acilis hatasiz/tasmasizdir; (360x760) imlec
//     acilisi da kayma yaratmaz.
//  6. Normal dokunma hata uretmez / alani kaydirmaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold/core/error/failures.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
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

Future<void> _boot(WidgetTester tester) async {
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
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Grafik alaninin ust (Y) konumu.
double _chartTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(InteractiveChart)).dy;

void main() {
  testWidgets(
      'imlec acilirken / hareket ederken / kapanirken grafik alani KAYMAZ '
      '(kok neden regresyonu)', (tester) async {
    await _boot(tester);

    final topBefore = _chartTop(tester);
    final center = tester.getCenter(find.byType(InteractiveChart));

    // Uzun basma (imlec acilir) - parmak hala basili.
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull,
        reason: 'imlec acilisinda hata uretilmemeli');
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'ust baslik imlec moduna gecmeli');
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'OHLC bari imlec mumuna gecmeli');

    final topEngaged = _chartTop(tester);
    expect(topEngaged, topBefore,
        reason: 'IMLEC ACILIRKEN GRAFIK ALANI KAYMAMALI - bu, cihazda '
            'gorulen "cizgi parmagin ustunde / dokunma tepki yok" '
            'sorununun kok nedendir (baslik yuksekligi degisiyordu)');

    // Parmak hafifce hareket - imlec takip eder, alan yine sabit.
    await gesture.moveTo(center + const Offset(30, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(_chartTop(tester), topBefore,
        reason: 'imlec hareket ederken de kayma olmamali');

    // Parmak kaldir - imlec kapanir, canli moda donulur.
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Geçmiş mum'), findsNothing,
        reason: 'imlec kapaninca canli moda donulmeli');
    expect(_chartTop(tester), topBefore,
        reason: 'imlec KAPANIRKEN de grafik alani kaymamali (ziplama yok)');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('hizli dilim degisimlerinden sonra imlec hala calisir',
      (tester) async {
    await _boot(tester);

    // Hizli ardışik dilim degisimleri (kullanici senaryosu: hizli secim).
    for (final label in ['1 dk', '15 dk', '4 sa', '5 dk']) {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(tester.takeException(), isNull,
        reason: 'hizli dilim degisimlerinde hata olmamali');
    expect(find.byType(InteractiveChart), findsOneWidget);

    // Degisimlerden hemen sonra uzun basma.
    final topBefore = _chartTop(tester);
    final center = tester.getCenter(find.byType(InteractiveChart));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'hizli dilim degisimlerinden sonra imlec acilmali');
    expect(_chartTop(tester), topBefore,
        reason: 'imlec acilisi kayma yaratmamali');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('normal dokunma hata uretmez ve grafik alani kaydirmaz',
      (tester) async {
    await _boot(tester);

    final topBefore = _chartTop(tester);
    final center = tester.getCenter(find.byType(InteractiveChart));

    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull,
        reason: 'sade dokunma hata uretmemeli');
    expect(_chartTop(tester), topBefore,
        reason: 'dokunma grafik alanini kaydirmamali');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dar ekranda (360x640) acilis hatasiz ve tasmaz', (tester) async {
    // Not: bu boyutta baslik darliga gore genisler ve grafik alani kuculur;
    // asil amac, acilis boyunca YATAY TASMA (RenderFlex) veya baska hata
    // uretilmemesidir (eski kodda sekmeler satiri 33px tasiyordu).
    tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _boot(tester);

    final bootEx = tester.takeException();
    expect(bootEx, isNull, reason: 'acilista hata/tasma olmamali: $bootEx');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dar ekranda (360x760) imlec acilirken grafik kaymaz',
      (tester) async {
    // 360x760: dar telefon boyutu; yuzde yazilari (test fontu Ahem) genis
    // oldugu icin 640 yukseklikte grafik alani neredeyse sifirlanir ve
    // imlec fisilen alanda acilamaz. 760'da ana grafik alani gercek
    // bir dar telefondaki gibi anlamli bosluga sahiptir.
    tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _boot(tester);

    final bootEx = tester.takeException();
    expect(bootEx, isNull, reason: 'yalnizca acilista (canli baslik): $bootEx');

    final topBefore = _chartTop(tester);
    final center = tester.getCenter(find.byType(InteractiveChart));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'dar ekranda da imlec GERCEKTEN acilmali (test bos gecmemeli)');
    expect(_chartTop(tester), topBefore,
        reason: 'dar ekranda (baslik/OHLC satir sayisi farkli sarabilir) '
            'imlec acilisi da kayma yaratmamali');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_chartTop(tester), topBefore);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
