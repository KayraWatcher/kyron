// Gecici arastirma testi - crosshair release davranisini olcmek icin.
// Gercek uygulamadaki gibi interaction'i geri besleyerek.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/features/charts/chart_types.dart';
import 'package:gold/features/charts/interactive_chart.dart';

List<Candle> _series(int n) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: 1700000000000 + i * 86400000,
          open: 100 + i.toDouble(),
          high: 101 + i.toDouble(),
          low: 99 + i.toDouble(),
          close: 100.5 + i.toDouble(),
          volume: 1000,
        ),
    ];

class Host extends StatefulWidget {
  const Host({super.key, required this.onEvents});
  final void Function(List<ChartInteraction>) onEvents;
  @override
  State<Host> createState() => _HostState();
}

class _HostState extends State<Host> {
  ChartInteraction _i = ChartInteraction.empty;
  final _log = <ChartInteraction>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: InteractiveChart(
            candles: _series(60),
            chartType: ChartType.candlestick,
            interaction: _i,
            onInteractionChanged: (i) {
              _log.add(i);
              widget.onEvents(_log);
              setState(() => _i = i);
            },
            onCrosshairRelease: () {},
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('long press + release crosshair temizleniyor mu? (geri besleme ile)',
      (tester) async {
    List<ChartInteraction> log = const [];
    await tester.pumpWidget(Host(onEvents: (e) => log = e));

    final center = tester.getCenter(find.byType(InteractiveChart));
    final g = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('EVENTS: ${log.length}');
    for (final i in log) {
      // ignore: avoid_print
      print('  showCrosshair=${i.showCrosshair} idx=${i.crosshairIndex}');
    }
    final last = log.isNotEmpty ? log.last : null;
    expect(last, isNotNull);
    expect(last!.showCrosshair, isFalse, reason: 'crosshair kapanmali');
    expect(last.crosshairIndex, isNull,
        reason: 'release sonrasi secili mum temizlenmeli');
  });
}
