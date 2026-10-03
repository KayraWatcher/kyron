// GOLD - temel pim (smoke) testi.
//
// Kapsam: uygulama acilabilir, kabuk ve 5 sekme olusturulabilir.
// Ayrintili birim testleri `test/` altindaki diger dosyalarda toplanir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('GOLD uygulaması açılır ve 5 sekmeli kabuğu oluşturur',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GoldApp()),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(GoldApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // 5 sekme de kabukta tanimli mi? (Material 3 `NavigationBar`)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));

    // Ag baglantisi olmayan test ortaminda "Ana Sayfa" hazir durumda olmali.
    expect(find.text('Ana Sayfa'), findsWidgets);

    // Ağaç bosaltilir; alarm izleyicisinin periyodik zamanlayicisi
    // aksi halde test sonunda "pending timer" hatasi verir.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
