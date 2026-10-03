// Gecici arastirma testi - crosshair release sonrasi HEADER canli moda
// donuyor mu? Gercek crosshairCandleProvider ile.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/features/asset_detail/asset_detail_providers.dart';
import 'package:gold/features/charts/chart_types.dart';
import 'package:gold/features/charts/interactive_chart.dart';

const _asset = 'test-asset';

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

class Section extends ConsumerStatefulWidget {
  const Section({super.key});
  @override
  ConsumerState<Section> createState() => _SectionState();
}

class _SectionState extends ConsumerState<Section> {
  ChartInteraction _i = ChartInteraction.empty;
  List<Candle> _last = const [];

  void _onInteraction(ChartInteraction i) {
    final provider = crosshairCandleProvider(_asset);
    final next = resolveCrosshairCandle(
      _last,
      i.showCrosshair ? i.crosshairIndex : null,
    );
    final prev = ref.read(provider);
    if (crosshairChanged(prev, next)) {
      ref.read(provider.notifier).pick(next);
    }
    setState(() => _i = i);
  }

  @override
  Widget build(BuildContext context) {
    final picked = ref.watch(crosshairCandleProvider(_asset));
    final candles = _series(60);
    _last = candles;
    return Column(
      children: [
        Text(picked == null ? 'LIVE' : 'HISTORICAL ${picked.time}',
            key: const Key('header')),
        SizedBox(
          width: 400,
          height: 300,
          child: InteractiveChart(
            candles: candles,
            chartType: ChartType.candlestick,
            interaction: _i,
            onInteractionChanged: _onInteraction,
            onCrosshairRelease: () {
              ref.read(crosshairCandleProvider(_asset).notifier).pick(null);
            },
          ),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('release sonrasi header LIVE olmali', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Section())),
    ));
    await tester.pump();

    expect(tester.widget<Text>(find.byKey(const Key('header'))).data, 'LIVE');

    final center = tester.getCenter(find.byType(InteractiveChart));
    final g = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 50));

    // ignore: avoid_print
    print('DURING: ${tester.widget<Text>(find.byKey(const Key('header'))).data}');

    await g.up();
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('AFTER : ${tester.widget<Text>(find.byKey(const Key('header'))).data}');
    expect(tester.widget<Text>(find.byKey(const Key('header'))).data, 'LIVE',
        reason: 'release sonrasi header canli moda donmeli');
  });
}
