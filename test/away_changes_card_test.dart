// GOLD v2 - "Sen Yokken Ne Oldu?" bolumu: secim + Düzenle kontrolu (widget).
//
// Kurallar:
//  * Ilk acilista yalnizca VARSAYILAN secim gosterilir: Gram + Ceyrek.
//  * Gosterim sirasi kullanici seciminin sirasidir.
//  * "Düzenle" alt sayfayi acar; ekle / kaldir / sira yapilir.
//  * Secim ve sira uygulama yeniden acilinca korunur (prefs).
//  * En fazla 6 varlik; doluyken ekleme pasif.
//  * Yalnizca katalog varliklari secilebilir (fake asset yok).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/format/tr_format.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/features/home/away_changes_card.dart';
import 'package:gold/features/home/away_changes_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AwayChangeItem _item(String id, double pct) {
  final a = AssetCatalog.byId(id)!;
  return AwayChangeItem(
    assetId: id,
    name: a.name,
    symbol: a.symbol,
    changePercent: pct,
    currentPrice: 4100,
    previousPrice: 4000,
  );
}

// Veri sirasi BILINCLI farkli: gosterim secim sirasini izlemeli.
final AwayChangesData _data = AwayChangesData(
  items: [
    _item(AssetCatalog.ceyrekAltinId, 2.5),
    _item(AssetCatalog.gramAltinId, 1.1),
    _item(AssetCatalog.usdTryId, 0.7),
    _item(AssetCatalog.onsAltinId, 3.3),
    _item(AssetCatalog.yarimAltinId, 1.9),
  ],
  lastVisit: DateTime(2026, 10, 4, 9, 0),
);

Future<SharedPreferences> _boot(
  WidgetTester tester, {
  String? selection,
}) async {
  SharedPreferences.setMockInitialValues({
    if (selection != null) AwaySelectionNotifier.prefsKey: selection,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        awayChangesProvider.overrideWith((ref) async => _data),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AwayChangesCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

/// Kartin icindeki bir metin (alt sayfa acikken de karti ayirt eder).
Finder _inCard(String text) => find.descendant(
      of: find.byType(AwayChangesCard),
      matching: find.text(text),
    );

double _cardY(WidgetTester tester, String text) =>
    tester.getTopLeft(_inCard(text)).dy;

void main() {
  testWidgets(
      'ilk acilis: varsayilan secim Gram + Ceyrek gosterilir, baskasi gosterilmez',
      (tester) async {
    await _boot(tester);

    expect(find.text('Düzenle'), findsOneWidget,
        reason: 'bolume kalici Düzenle kontrolu eklenmeli');
    expect(_inCard(AssetCatalog.byId(AssetCatalog.gramAltinId)!.name),
        findsOneWidget);
    expect(_inCard(AssetCatalog.byId(AssetCatalog.ceyrekAltinId)!.name),
        findsOneWidget);
    expect(_inCard(AssetCatalog.byId(AssetCatalog.onsAltinId)!.name),
        findsNothing,
        reason: 'secimde olmayan varlik gosterilmez');
    expect(_inCard('Dolar / Türk Lirası'), findsNothing);

    expect(
      _cardY(tester, AssetCatalog.byId(AssetCatalog.gramAltinId)!.name),
      lessThan(_cardY(tester, AssetCatalog.byId(AssetCatalog.ceyrekAltinId)!.name)),
      reason: 'gosterim sirasi varsayilan secim sirasini izlemeli',
    );
  });

  testWidgets('Düzenle: ekle / sira / kaldir + varsayilana don + kalıcılık',
      (tester) async {
    final prefs = await _boot(tester);

    // ---- Alt sayfa acilir ----
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    expect(find.text('Sen Yokken Ne Oldu?'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Varlık ekle'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Varsayılana dön'),
          )
          .onPressed,
      isNull,
      reason: 'varsayilandayken sifirla pasif olmali',
    );

    // ---- Ekle: yalnizca katalog varliklari listelenir ----
    await tester.tap(find.widgetWithText(OutlinedButton, 'Varlık ekle'));
    await tester.pumpAndSettle();

    // Aday listesi katalog sirasiyla gelir; ilk ekrandaki "Yarim Altin"
    // uzerinden dogrulariz (katalog disi bir id listelenemez).
    final addName = AssetCatalog.byId(AssetCatalog.yarimAltinId)!.name;
    expect(find.text(addName), findsOneWidget,
        reason: 'desteklenen katalog varligi aday olarak listelenmeli');
    expect(
      find.text('olmayan-varlik'),
      findsNothing,
      reason: 'katalog disi varlik listelenemez',
    );

    // Katalog genisledigi icin aday listesi daha uzun olabilir; satir
    // gorunur degilse once kaydirilir (aksi halde dokunma iskalanir).
    await tester.ensureVisible(find.text(addName));
    await tester.pumpAndSettle();
    await tester.tap(find.text(addName));
    await tester.pumpAndSettle();

    // Eklenen varlik hem alt sayfada hem kartta (ayni veri) gorunur.
    expect(find.text(addName), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(_inCard(addName), findsOneWidget,
        reason: 'eklenen varlik kartta gosterilir');
    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      'gram-altin,ceyrek-altin,yarim-altin',
      reason: 'secim kalici olarak kaydedilmeli',
    );

    // ---- Sira: Gram asagi alinir ----
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aşağı taşı').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(
      _cardY(tester, AssetCatalog.byId(AssetCatalog.ceyrekAltinId)!.name),
      lessThan(_cardY(tester, AssetCatalog.byId(AssetCatalog.gramAltinId)!.name)),
      reason: 'sira degisikligi kartta gorunmeli',
    );
    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      'ceyrek-altin,gram-altin,yarim-altin',
    );

    // ---- Kaldir: Yarim (artik 3. satir) ----
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Seçimden kaldır').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(_inCard(addName), findsNothing,
        reason: 'kaldirilan varlik karttan dusmeli');
    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      'ceyrek-altin,gram-altin',
    );

    // ---- Varsayilana don ----
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Varsayılana dön'),
          )
          .onPressed,
      isNotNull,
      reason: 'varsayilan disinda iken sifirla aktif olmali',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Varsayılana dön'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      'gram-altin,ceyrek-altin',
      reason: 'varsayilana donunce kayit da varsayilana doner',
    );
    expect(
      _cardY(tester, AssetCatalog.byId(AssetCatalog.gramAltinId)!.name),
      lessThan(_cardY(tester, AssetCatalog.byId(AssetCatalog.ceyrekAltinId)!.name)),
    );
  });

  testWidgets('6 varlik doluyken ekleme pasif + ust sinir notu gosterilir',
      (tester) async {
    final six =
        AssetCatalog.all.take(6).map((a) => a.id).join(',');
    await _boot(tester, selection: six);

    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Seçimden kaldır'), findsNWidgets(6),
        reason: 'secimde en fazla 6 varlik olabilir');
    expect(
      find.widgetWithText(OutlinedButton, 'Varlık ekle'),
      findsNothing,
      reason: 'ust sinirda ekleme kontrolu gosterilmez (pasif)',
    );
    expect(
      find.text('En fazla 6 varlık gösterilebilir; eklemek için birini kaldırın.'),
      findsOneWidget,
      reason: 'ust sinir kullanicuya aciklanmali',
    );
  });

  testWidgets('secim tamamen bosaltilabilir; bolum Düzenle ile geri acilir',
      (tester) async {
    final prefs = await _boot(tester);

    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    // Varsayilan 2 satir: Gram ve Ceyrek'i kaldir.
    await tester.tap(find.byTooltip('Seçimden kaldır').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Seçimden kaldır').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Varlık yok. Aşağıdan ekleyin.'),
      findsOneWidget,
      reason: 'bos secim acik bir mesajla gosterilir',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      '',
      reason: 'bos secim de kaydedilir (geri donulebilir)',
    );
    expect(
      _inCard('Seçili varlıklarda belirgin bir değişim yok.'),
      findsOneWidget,
      reason: 'bos secimde bolum gizlenmez, Düzenle erisilebilir kalir',
    );

    // Geri don: alt sayfayi acip varsayilana don.
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Varsayılana dön'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(
      prefs.getString(AwaySelectionNotifier.prefsKey),
      'gram-altin,ceyrek-altin',
    );
    expect(
      _inCard(AssetCatalog.byId(AssetCatalog.gramAltinId)!.name),
      findsOneWidget,
    );
  });

  testWidgets('basliktaki gecen sure "on once" tekrari uretmez (regresyon)',
      (tester) async {
    await _boot(tester);

    // Kart basligindeki parantezli sure etiketi: "(7 dk once)" gibi.
    // relativeTime zaten "once" icermeli; karta tekrar eklenirse
    // "(7 dk once once)" oluyordu.
    final header = find.descendant(
      of: find.byType(AwayChangesCard),
      matching: find.textContaining('('),
    );
    expect(header, findsOneWidget, reason: 'sure etiketi kartta tek olmali');

    final label = tester.widget<Text>(header).data!;
    expect(
      label,
      '(${TrFormat.relativeTime(_data.lastVisit)})',
      reason: 'etiket birebir relativeTime sonucu; fazladan " once" yok',
    );
    expect(label.contains('önce önce'), isFalse);
  });
}
