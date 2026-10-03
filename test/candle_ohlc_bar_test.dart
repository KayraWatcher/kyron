// GOLD v2 - Faz E: OHLC + hacim + tarih ustbilgisi.
//
// Gereksinim 5: "Ustbilgi OHLC/hacim/tarih, capraz imlecin sectigi mumu
// yansitir."
//
// Kurallar:
//  * Imlec kapaliyken serideki **son** mum gosterilir.
//  * Imlec acikken imlecin isaret ettigi mumun degerleri VE tarihi gosterilir.
//  * Imlec gizlendiginde tekrar son muma donulur.
//  * Deger null ise "—" gosterilir; hicbir deger **uydurulmaz**.
//  * Bos seride satir tamamen gizlenir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/features/asset_detail/widgets/candle_ohlc_bar.dart';
import 'package:gold/features/charts/interactive_chart.dart';

DateTime _d(int y, int mo, int dd, int h) => DateTime(y, mo, dd, h);

Candle _c(
  DateTime t, {
  required double o,
  required double h,
  required double l,
  required double c,
  double? v,
}) =>
    Candle(
      time: t.millisecondsSinceEpoch,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v,
    );

Widget _wrap(List<Candle> candles, ChartInteraction i, {int decimals = 2}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: CandleOhlcBar(
            candles: candles,
            interaction: i,
            decimals: decimals,
          ),
        ),
      ),
    );

final List<Candle> _series = [
  _c(_d(2026, 10, 1, 10), o: 10, h: 12, l: 9, c: 11, v: 100),
  _c(_d(2026, 10, 2, 11), o: 20, h: 24, l: 18, c: 22, v: 200),
  _c(_d(2026, 10, 3, 12), o: 30, h: 36, l: 28, c: 34, v: 300),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CandleOhlcBar', () {
    testWidgets('varsayilan: serideki SON mumun degerleri ve tarihi',
        (tester) async {
      await tester.pumpWidget(
        _wrap(_series, const ChartInteraction(showCrosshair: true)),
      );

      // Son mum (3 Ekim 2026, 12:00)
      expect(find.textContaining('Son mum'), findsOneWidget);
      expect(find.textContaining('3 Ekim 2026'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('30,00'), findsOneWidget, reason: 'A (acilis)');
      expect(find.text('36,00'), findsOneWidget, reason: 'Y (yuksek)');
      expect(find.text('28,00'), findsOneWidget, reason: 'D (dusuk)');
      expect(find.text('34,00'), findsOneWidget, reason: 'K (kapanis)');
      expect(find.text('Hacim'), findsOneWidget);
      // Ilk mumun degerleri GOSTERILMEMELI.
      expect(find.text('10,00'), findsNothing);
    });

    testWidgets('imlec ACIKKEN imlecin mumu gosterilir (gereksinim 5)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          _series,
          const ChartInteraction(showCrosshair: true, crosshairIndex: 0),
        ),
      );

      expect(find.textContaining('1 Ekim 2026'), findsOneWidget,
          reason: 'tarih imlecin mumuna gitmeli');
      expect(find.textContaining('Son mum'), findsNothing,
          reason: 'imlec acikken "son mum" yazmamali');
      expect(find.text('10,00'), findsOneWidget, reason: 'A');
      expect(find.text('12,00'), findsOneWidget, reason: 'Y');
      expect(find.text('9,00'), findsOneWidget, reason: 'D');
      expect(find.text('11,00'), findsOneWidget, reason: 'K');
      expect(find.text('30,00'), findsNothing,
          reason: 'son mumun degerleri kalmamali');
    });

    testWidgets('ortadaki mum secilebilir', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _series,
          const ChartInteraction(showCrosshair: true, crosshairIndex: 1),
        ),
      );

      expect(find.textContaining('2 Ekim 2026'), findsOneWidget);
      expect(find.text('20,00'), findsOneWidget, reason: 'A');
      expect(find.text('22,00'), findsOneWidget, reason: 'K');
    });

    testWidgets('imlec gizlenince (pan/bas birakma) son muma donulur',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          _series,
          const ChartInteraction(
            showCrosshair: false,
            crosshairIndex: 0,
          ),
        ),
      );

      expect(find.textContaining('Son mum'), findsOneWidget);
      expect(find.textContaining('3 Ekim 2026'), findsOneWidget);
      expect(find.text('30,00'), findsOneWidget);
    });

    testWidgets('indeks serinin disindaysa sinirlanir (kaydirma Sonrasinda)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          _series,
          const ChartInteraction(showCrosshair: true, crosshairIndex: 999),
        ),
      );

      expect(find.textContaining('3 Ekim 2026'), findsOneWidget,
          reason: 'son muma sikistirilmali');
      expect(find.text('30,00'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          _series,
          const ChartInteraction(showCrosshair: true, crosshairIndex: -5),
        ),
      );
      expect(find.textContaining('1 Ekim 2026'), findsOneWidget,
          reason: 'ilk muma sikistirilmali');
      expect(find.text('10,00'), findsOneWidget);
    });

    testWidgets('bos seride hicbir satir cizilmez (uydurma veri yok)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const <Candle>[], const ChartInteraction(showCrosshair: true)),
      );

      expect(find.byType(CandleOhlcBar), findsOneWidget);
      expect(find.text('Hacim'), findsNothing);
      expect(find.textContaining('Son mum'), findsNothing);
    });

    testWidgets('deger null ise "—" gosterilir, 0 UYDURULMAZ', (tester) async {
      final noVol = <Candle>[
        Candle(
          time: _d(2026, 10, 5, 9).millisecondsSinceEpoch,
          open: 5,
          high: 6,
          low: 4,
          close: 5.5,
          volume: null,
        ),
      ];

      await tester.pumpWidget(
        _wrap(noVol, const ChartInteraction(showCrosshair: true)),
      );

      expect(find.text('5,00'), findsOneWidget, reason: 'A');
      expect(find.text('6,00'), findsOneWidget, reason: 'Y');
      expect(find.text('4,00'), findsOneWidget, reason: 'D');
      expect(find.text('5,50'), findsOneWidget, reason: 'K');
      expect(find.text('0,00'), findsNothing,
          reason: 'hacim yokken 0 GOSTERILMEMELI');
      expect(find.text('—'), findsOneWidget, reason: 'hacim yok = tire');
    });
  });

  // Cihazda yasanan hata: satir yatay kaydirma icindeydi ve sigmayan
  // D / K / Hacim **gosterilmiyordu** (semantik agacindan da dusuyordu).
  // Bu test o degerlerin her kosulda gorunur oldugunu zorlar.
  group('CandleOhlcBar gorunurluk', () {
    Future<void> expectAllVisible(WidgetTester tester, double width) async {
      // Test yuzeyini kucultmeliyiz: `SizedBox(width: ..)` pumpWidget'in
      // asagidan verdigi TIGHT 800x600 kisitlarini ezeceginden isi goremez.
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(_series, const ChartInteraction(showCrosshair: true)),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(MaterialApp)).width, width);

      const labels = ['A', 'Y', 'D', 'K', 'Hacim'];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: '$label bulunmali');
      }

      // Tarih + A/Y/D/K + Hacim degerleri de ayni sekilde gorunur olmali.
      final values = <Finder>[
        find.textContaining('Son mum'),
        find.text('30,00'),
        find.text('36,00'),
        find.text('28,00'),
        find.text('34,00'),
      ];
      for (final f in values) {
        expect(f, findsOneWidget);
      }

      // Hicbir hucre ekran disina tasmasin (kaydirma/gizleme olmasin).
      for (final f in <Finder>[...values, ...labels.map(find.text)]) {
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(-0.01),
            reason: '$f soldan tasmali');
        expect(r.right, lessThanOrEqualTo(width + 0.01),
            reason: '$f sagdan tasmali - ekranda GORUNMEZ');
        expect(r.top, greaterThanOrEqualTo(-0.01));
        expect(r.bottom, lessThanOrEqualTo(tester.getSize(find.byType(MaterialApp)).height + 0.01),
            reason: '$f dikeyde asagi tasmali');
      }
    }

    testWidgets('gercek cihaz genisliginde (1080px / 440dpi ~ 393) tumu gorunur',
        (tester) async {
      await expectAllVisible(tester, 393);
    });

    testWidgets('dar ekranda (320) bile hicbir deger kaybolmaz',
        (tester) async {
      await expectAllVisible(tester, 320);
    });
  });
}
