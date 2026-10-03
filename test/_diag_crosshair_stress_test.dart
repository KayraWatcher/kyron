// Diagnostik (gecici) - Asset Detail: uzun basma + hizli capraz imlec stresi.
//
// Cihazda raporlanan hata:
//   * long press -> crosshair acilir
//   * ~5-15 saniye boyunca hizli saga/sola hareket
//   * bir noktadan sonra grafik dokunmaya cevap vermez
//   * ekrani kapatip acinca bile bazen tekrar olur
//
// Bu test gercek ekran (AssetDetailScreen + _ChartSection + InteractiveChart +
// debounce + crosshairCandleProvider) uzerinde olcum yapar:
//   1. Sure buyumesu var mi?  (buyuyen collection / O(n^2) belirtisi)
//   2. Stres sonrasi YENI bir gesture hala yanitliyor mu? (recognizer kilidi)
//   3. Hic exception firlatiliyor mu? (pointer event zincirinde patlama)
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
import 'package:gold/features/asset_detail/widgets/candle_ohlc_bar.dart';
import 'package:gold/features/charts/interactive_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StressSource implements MarketDataProvider {
  const StressSource();

  @override
  String get id => 'stress';

  @override
  String get displayName => 'Stress';

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
    return Success(
      CandleSeries(
        assetId: assetId,
        interval: interval,
        candles: _series(limit),
      ),
    );
  }
}

List<Candle> _series(int n) {
  final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
  return [
    for (var i = 0; i < n; i++)
      Candle(
        time: base + i * 86400000,
        open: 2000 + (i % 50) * 3.0,
        high: 2012 + (i % 50) * 3.0,
        low: 1992 + (i % 50) * 3.0,
        close: 2006 + (i % 50) * 3.0,
        volume: 1000 + i * 10.0,
      ),
  ];
}

const String assetId = 'ons-altin';

Future<void> _boot(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        marketSourcesProvider.overrideWithValue(const [StressSource()]),
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
  expect(find.byType(CandleOhlcBar), findsOneWidget);

  // initState'teki gosterge mikro gorevi + ilk render.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('stres: uzun sureli hizli crosshair - buyume / olum gesture',
      (tester) async {
    await _boot(tester);

    final chart = find.byType(InteractiveChart);
    final topLeft = tester.getTopLeft(chart);
    final size = tester.getSize(chart);
    // Cizim alani (RSI panelinin ustunde kalan plot).
    final pressPoint =
        Offset(topLeft.dx + size.width * 0.5, topLeft.dy + size.height * 0.30);

    // ---- 1) long press: crosshair acilmali ----
    final gesture = await tester.startGesture(pressPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'long press ile crosshair acilmali');

    // ---- 2) hizli saga/sola hareket (50 karelik olcum paketleri) ----
    const packages = 8; // 8 x 50 = 400 paket = 800 hareket ~ 26 sn simule
    const perPackage = 50;
    final batches = <double>[];

    for (var p = 0; p < packages; p++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < perPackage; i++) {
        await gesture.moveBy(const Offset(32, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(-32, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      sw.stop();
      batches.add(sw.elapsedMicroseconds / 1000.0);
    }

    final first = batches.first;
    final last = batches.last;
    final avg = batches.reduce((a, b) => a + b) / batches.length;
    // Buyume orani belirgin sekilde 1'in uzerine cikmamali: islenmemis olay
    // kuyrugu ya da kontrol disi birikim olsaydi paketler katlanarak uzardi
    // (ekranin donmasi tam olarak bu gorunumdeydi).
    expect(last / first, lessThan(3.0),
        reason: 'stres paketleri buyumemeli: ilk=${first.toStringAsFixed(0)}ms '
            'son=${last.toStringAsFixed(0)}ms '
            'ort=${avg.toStringAsFixed(1)}ms');

    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'hareket sirasinda crosshair acik kalmali');

    final duringException = tester.takeException();
    expect(duringException, isNull,
        reason: 'hareket sirasinda exception: $duringException');

    // ---- 3) parmak birakildi: crosshair kapanmali ----
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.my_location_rounded), findsNothing,
        reason: 'parmak kalkinca crosshair kapanmali');

    // ---- 4) YENI gesture hala yanitliyor mu? ----
    final g2 = await tester.startGesture(pressPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'STRES SONRASI yeni long press hala yanitmali (donma yok)');

    await g2.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await g2.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));

    final endException = tester.takeException();
    expect(endException, isNull,
        reason: 'stres sonrasi exception: $endException');

    await _teardown(tester);
  });

  testWidgets('stres: stres sonrasi ust baslik (secili mum) temizleniyor mu',
      (tester) async {
    await _boot(tester);

    final chart = find.byType(InteractiveChart);
    final topLeft = tester.getTopLeft(chart);
    final size = tester.getSize(chart);
    final pressPoint =
        Offset(topLeft.dx + size.width * 0.5, topLeft.dy + size.height * 0.30);

    final gesture = await tester.startGesture(pressPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));

    // Biraz hareket -> ust baslik "Gecmis mum" moduna gecmeli.
    const dx = 20.0;
    const steps = 5;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(dx, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'hareket sirasinda ust baslik secili muma gecmeli');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Geçmiş mum'), findsNothing,
        reason: 'parmak kalkinca ust baslik canli moda donmeli');

    // ---- ikinci uzun basma: imlec **AYNI indekste** (birakinilan yerden)
    //      basilsa bile baslik tekrar "Gecmis mum"a gecmeli. Eski kodda
    //      "son bildirilen indeks ayni" diye pick yutulurdu. ----
    final g2 = await tester.startGesture(pressPoint + const Offset(dx * steps, 0));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'ikinci long press imleci acmali');
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'ikinci long press ust basligi da secili muma gecirmeli');

    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Geçmiş mum'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('stres: once pan (kaydir) sonra long press hala acilir mi?',
      (tester) async {
    await _boot(tester);

    final chart = find.byType(InteractiveChart);
    final topLeft = tester.getTopLeft(chart);
    final size = tester.getSize(chart);
    final y = topLeft.dy + size.height * 0.30;

    final dbg0 = tester.widget<CandleOhlcBar>(find.byType(CandleOhlcBar));
    expect(dbg0.interaction.crosshairIndex, isNull,
        reason: 'ilk acilista crosshair kapali olmali');

    // Once kaydirma (pan): `_onScaleStart` imleci `hideCrosshair` ile kapatir.
    final pan = await tester.startGesture(Offset(topLeft.dx + size.width * 0.3, y));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await pan.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pan.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.my_location_rounded), findsNothing,
        reason: 'pan sirasinda imlec kapali kalmali');

    // Simdi long press: imlec ACILMALI (eski kodda showCrosshair kalici
    // false oldugu icin bir daha acilmazdi).
    final lp = await tester.startGesture(
        Offset(topLeft.dx + size.width * 0.5, y));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget,
        reason: 'PAN SONRASI long press imleci acmali (regresyon)');

    await lp.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Geçmiş mum'), findsOneWidget,
        reason: 'pan sonrasi baslik da secili muma gecmeli');

    await lp.up();
    await tester.pump(const Duration(milliseconds: 300));

    final exc = tester.takeException();
    expect(exc, isNull);

    await _teardown(tester);
  });
}
