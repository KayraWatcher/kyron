// GOLD v2 - Faz E: pan/zoom penceresi (ChartWindow).
//
// Gereksinim 4: "Grafik suruklenmesi gecmise gider; sag tarafta **uydurma
// bosluk** birakilmaz."
//
// Bu testler pencere kurallarini dogrular:
//  * `first + visible <= n` her durumda  (sagda bosluk yok)
//  * `first >= 0`                        (sol tarafta uydurma mum yok)
//  * gorunur sayi seriyi asla asmaz      (RangeError riski yok)
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/features/charts/chart_geometry.dart';

void main() {
  group('ChartWindow.clampVisible', () {
    test('verilen deger sinirlar icinde sikistirilir', () {
      expect(ChartWindow.clampVisible(0, 1000), ChartWindow.minVisible);
      expect(ChartWindow.clampVisible(50, 1000), 50);
      expect(ChartWindow.clampVisible(9999, 1000), ChartWindow.maxVisible);
    });

    test('kisa seride gorunur sayi seriyi ASLA ASMAZ', () {
      // Eski kod: `5.clamp(8, 500) == 8` -> zoom'da `clamp(8, 5)`
      // RangeError uretiyordu.
      expect(ChartWindow.clampVisible(100, 5), 5);
      expect(ChartWindow.clampVisible(0, 5), 5);
      expect(ChartWindow.clampVisible(100, 1), 1);
    });

    test('bos seri sifir dondurur', () {
      expect(ChartWindow.clampVisible(10, 0), 0);
    });
  });

  group('ChartWindow.clampFirst - sagda bosluk YOK', () {
    test('saga asiri suruklemede son mum sag kenara dayanir', () {
      const n = 200;
      const visible = 50;
      final first = ChartWindow.clampFirst(9999, visible, n);
      expect(first, n - visible);
      expect(first + visible, n, reason: 'sagda bosluk kalmamali');
    });

    test('sola asiri suruklemede ilk mum sol kenara dayanir', () {
      expect(ChartWindow.clampFirst(-9999, 50, 200), 0);
    });

    test('icindeki deger aynen korunur', () {
      expect(ChartWindow.clampFirst(120, 50, 200), 120);
      expect(ChartWindow.clampFirst(0, 50, 200), 0);
      expect(ChartWindow.clampFirst(150, 50, 200), 150);
    });

    test('kisa seride de invariant saglanir', () {
      for (var n = 1; n <= 12; n++) {
        for (var v = 0; v <= 12; v++) {
          final f = ChartWindow.clampFirst(1000, v, n);
          final vis = ChartWindow.clampVisible(v, n);
          expect(f, greaterThanOrEqualTo(0), reason: 'n=$n v=$v');
          expect(f + vis, lessThanOrEqualTo(n),
              reason: 'sagda bosluk: n=$n v=$v');
        }
      }
    });
  });

  group('ChartWindow.panFirst', () {
    test('saga surukleme (dx>0) eski mumlara goturur', () {
      const n = 300;
      const visible = 60;
      const plotWidth = 300.0;

      final start = ChartWindow.clampFirst(n - visible, visible, n);
      final back = ChartWindow.panFirst(
        first: start,
        dx: 150,
        visible: visible,
        n: n,
        plotWidth: plotWidth,
      );
      expect(back, lessThan(start), reason: 'daha eski mumlar gorunmeli');
      expect(back, greaterThanOrEqualTo(0));
    });

    test('sola surukleme (dx<0) yeni mumlara goturur', () {
      const n = 300;
      const visible = 60;
      const plotWidth = 300.0;

      final forward = ChartWindow.panFirst(
        first: 0,
        dx: -150,
        visible: visible,
        n: n,
        plotWidth: plotWidth,
      );
      expect(forward, greaterThan(0));
      expect(forward + visible, lessThanOrEqualTo(n));
    });

    test('asiri surukleme sinirlarda durur (invariant)', () {
      const n = 240;
      const visible = 40;
      const plotWidth = 320.0;

      var f = ChartWindow.clampFirst(0, visible, n);
      for (var i = 0; i < 100; i++) {
        f = ChartWindow.panFirst(
          first: f,
          dx: -60,
          visible: visible,
          n: n,
          plotWidth: plotWidth,
        );
        expect(f + visible, lessThanOrEqualTo(n),
            reason: 'sagda bosluk olmamali');
        expect(f, greaterThanOrEqualTo(0));
      }
      expect(f, n - visible, reason: 'son mum sag kenarda kalmali');

      for (var i = 0; i < 200; i++) {
        f = ChartWindow.panFirst(
          first: f,
          dx: 60,
          visible: visible,
          n: n,
          plotWidth: plotWidth,
        );
        expect(f, greaterThanOrEqualTo(0));
        expect(f + visible, lessThanOrEqualTo(n));
      }
      expect(f, 0, reason: 'en eski mum sol kenarda');
    });

    test('gecersiz genislikte degisiklik olmaz', () {
      final f = ChartWindow.panFirst(
        first: 10,
        dx: 100,
        visible: 40,
        n: 100,
        plotWidth: 0,
      );
      expect(f, 10);
    });
  });

  group('ChartWindow.zoomVisible / scaledVisible', () {
    test('yakinlastirma seriyi asmaz', () {
      expect(
        ChartWindow.zoomVisible(current: 50, factor: 0.1, n: 200),
        greaterThanOrEqualTo(ChartWindow.minVisible),
      );
      expect(
        ChartWindow.zoomVisible(current: 50, factor: 10, n: 200),
        lessThanOrEqualTo(200),
      );
    });

    test('kisa seride zoom asla RangeError vermez', () {
      // Eski kod: `(x).clamp(8, min(500, 5))` -> `clamp(8, 5)` RangeError.
      for (final factor in const [0.2, 0.5, 1.0, 2.0, 10.0]) {
        final v = ChartWindow.zoomVisible(current: 5, factor: factor, n: 5);
        expect(v, greaterThanOrEqualTo(1));
        expect(v, lessThanOrEqualTo(5));
      }
    });

    test('parmakli olcekleme de sinirli', () {
      for (final scale in const [0.1, 0.5, 1.0, 3.0, 50.0]) {
        final v = ChartWindow.scaledVisible(base: 40, scale: scale, n: 300);
        expect(v, greaterThanOrEqualTo(ChartWindow.minVisible));
        expect(v, lessThanOrEqualTo(300));
      }
    });

    test('gecersiz olcek carpmadan once guvenli', () {
      expect(ChartWindow.scaledVisible(base: 40, scale: 0, n: 300), 40);
      expect(ChartWindow.scaledVisible(base: 40, scale: -2, n: 300), 40);
    });

    test('bos seri sifir dondurur', () {
      expect(ChartWindow.zoomVisible(current: 5, factor: 2, n: 0), 0);
      expect(ChartWindow.scaledVisible(base: 5, scale: 2, n: 0), 0);
      expect(ChartWindow.clampFirst(5, 5, 0), 0);
      expect(
        ChartWindow.panFirst(first: 5, dx: 10, visible: 5, n: 0, plotWidth: 100),
        0,
      );
    });
  });
}
