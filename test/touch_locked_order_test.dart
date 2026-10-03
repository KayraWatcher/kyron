// GOLD v2 - Faz D: dokunma kilidi (TouchLockedOrder).
//
// Gereksinim: "Yeniden siralama, kullanici bir kaleme dokunurken listeyi
// hareket ettirmemeli."
//
// Kurallar dogrulanir:
//  * Parmak yokken sira degisikligi aninda uygulanir.
//  * Parmak ekrandayken sira **ertelenir**; eski sira korunur.
//  * Parmak kaldirildiginda ertelenen sira tek seferde uygulanir.
//  * Iki parmakta, ikisi de kalkmadan uygulanmaz.
//  * Parmak iptalinde (cancel) da uygulanir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/features/home/touch_locked_order.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Builder'in son urettigi sira - test bunu okur.
  List<String> seen = const <String>[];

  Widget wrap(List<String> desired) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: TouchLockedOrder(
            desired: desired,
            builder: (ids) {
              seen = ids;
              return Container(
                width: 300,
                height: 300,
                color: const Color(0xFF222222),
              );
            },
          ),
        ),
      );

  setUp(() => seen = const <String>[]);

  group('TouchLockedOrder', () {
    testWidgets('ilk kurulumda istenen sira gosterilir', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));
      expect(seen, const ['a', 'b', 'c']);
    });

    testWidgets('parmak yokken degisiklik aninda uygulanir', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));
      await tester.pumpWidget(wrap(const ['c', 'b', 'a']));
      expect(seen, const ['c', 'b', 'a'],
          reason: 'kimse dokunmuyorsa liste hemen siralanmali');
    });

    testWidgets('parmak EKRANDAYKEN sira degismez (kilit)', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));

      final g = await tester.startGesture(const Offset(60, 60));
      await tester.pump();

      // Fiyat tik'i geldi / siralama istegi degisti.
      await tester.pumpWidget(wrap(const ['c', 'b', 'a']));
      expect(seen, const ['a', 'b', 'c'],
          reason:
              'kullanici bir karta basili tutarken kartlar YER DEGISTIRMEMELI');

      await g.up();
      await tester.pump();
      expect(seen, const ['c', 'b', 'a'],
          reason: 'parmak kalkinca ertelenen sira uygulanmali');
    });

    testWidgets('basili tutarken birden fazla degisiklik birikir ve sonuncusu'
        ' uygulanir', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c', 'd']));

      final g = await tester.startGesture(const Offset(60, 60));
      await tester.pump();

      await tester.pumpWidget(wrap(const ['d', 'c', 'b', 'a']));
      await tester.pumpWidget(wrap(const ['b', 'a', 'd', 'c']));
      expect(seen, const ['a', 'b', 'c', 'd'], reason: 'kilit surmeli');

      await g.up();
      await tester.pump();
      expect(seen, const ['b', 'a', 'd', 'c'],
          reason: 'son istenen sira uygulanmali');
    });

    testWidgets('iki parmakta ikisi de kalkmadan uygulanmaz', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));

      final g1 = await tester.startGesture(const Offset(40, 40));
      final g2 = await tester.startGesture(const Offset(200, 200));
      await tester.pump();

      await tester.pumpWidget(wrap(const ['c', 'b', 'a']));
      expect(seen, const ['a', 'b', 'c']);

      await g1.up();
      await tester.pump();
      expect(seen, const ['a', 'b', 'c'],
          reason: 'hala bir parmak ekranda');

      await g2.up();
      await tester.pump();
      expect(seen, const ['c', 'b', 'a']);
    });

    testWidgets('parmak iptal edilirse (cancel) kilit kalkar', (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));

      final g = await tester.startGesture(const Offset(60, 60));
      await tester.pump();
      await tester.pumpWidget(wrap(const ['c', 'b', 'a']));
      expect(seen, const ['a', 'b', 'c']);

      await g.cancel();
      await tester.pump();
      expect(seen, const ['c', 'b', 'a']);
    });

    testWidgets('kilit altindayken ayni sira istegi sorun cikarmaz',
        (tester) async {
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));
      final g = await tester.startGesture(const Offset(60, 60));
      await tester.pump();

      // Ayni sira tekrar gonder (orn. fiyatlar degismedi).
      await tester.pumpWidget(wrap(const ['a', 'b', 'c']));
      expect(seen, const ['a', 'b', 'c']);

      await g.up();
      await tester.pump();
      expect(seen, const ['a', 'b', 'c']);
    });
  });
}
