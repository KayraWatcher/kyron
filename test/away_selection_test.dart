// GOLD v2 - "Sen Yokken Ne Oldu?" varlik secimi.
//
// Kurallar:
//  * Ilk kurulumda (kayit yoksa) Gram Altin + Ceyrek Altin gelir.
//  * Secim yalnizca AssetCatalog canonical id'lerinden olur (uydurma yok).
//  * Ekle / kaldir / sira + kalıcılık (uygulama yeniden acilinca korunur).
//  * En fazla awaySelectionMax varlik; ustu asilmaz.
//  * applyAwaySelection: yalnizca secimi filtreler + kullanici sirasini uygular.
//  * Fiyat/analiz mantigina dokunulmaz (saf fonksiyon + durum testi).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/features/home/away_changes_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AwaySelectionNotifier - varsayilan ve kalıcılık', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    ProviderContainer withPrefs() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );

    test('kayit YOKSA varsayilan: Gram Altin + Ceyrek Altin', () {
      final c = withPrefs();
      addTearDown(c.dispose);

      expect(
        c.read(awaySelectionProvider),
        [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId],
        reason: 'ilk acilista Gram + Ceyrek gelmeli',
      );
      expect(c.read(awaySelectionProvider.notifier).isDefault, isTrue);
    });

    test('prefs yoksa uygulama COKMEZ, varsayilan kullanilir', () {
      final c = ProviderContainer(); // override yok
      addTearDown(c.dispose);
      expect(
        c.read(awaySelectionProvider),
        [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId],
      );
    });

    test('secim saklanir ve uygulama yeniden acilinca KORUNUR (sira dahil)',
        () async {
      final c1 = withPrefs();
      addTearDown(c1.dispose);

      final n1 = c1.read(awaySelectionProvider.notifier);
      n1
        ..add(AssetCatalog.onsAltinId)
        ..add(AssetCatalog.usdTryId)
        ..remove(AssetCatalog.ceyrekAltinId)
        ..move(AssetCatalog.onsAltinId, -1);

      await prefs.reload();

      // Yeni container = uygulama yeniden baslatildi.
      final c2 = withPrefs();
      addTearDown(c2.dispose);

      final restored = c2.read(awaySelectionProvider);
      expect(
        restored,
        [
          // move(ons, -1): ons, gram'in one gecer -> [ons, gram, usd]
          AssetCatalog.onsAltinId,
          AssetCatalog.gramAltinId,
          AssetCatalog.usdTryId,
        ],
        reason: 'secim ve sira yeniden acilista korunmali',
      );
    });

    test('bozuk / tamami gecersiz kayit varsayilana duser (uydurma yok)',
        () async {
      await prefs.setString(
        AwaySelectionNotifier.prefsKey,
        'olmayan-varlik,sahte-id',
      );
      await prefs.reload();

      final c = withPrefs();
      addTearDown(c.dispose);
      expect(
        c.read(awaySelectionProvider),
        [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId],
      );
    });

    test('gecersiz id kayittan elenir, gecerliler korunur', () async {
      await prefs.setString(
        AwaySelectionNotifier.prefsKey,
        'olmayan,usd-try,ceyrek-altin,olmayan2',
      );
      await prefs.reload();

      final c = withPrefs();
      addTearDown(c.dispose);
      expect(
        c.read(awaySelectionProvider),
        [AssetCatalog.usdTryId, AssetCatalog.ceyrekAltinId],
      );
    });

    test('kayit ust siniri asarsa ilk 6 varlik alinir', () async {
      await prefs.setString(
        AwaySelectionNotifier.prefsKey,
        AssetCatalog.all.map((a) => a.id).join(','),
      );
      await prefs.reload();

      final c = withPrefs();
      addTearDown(c.dispose);
      final sel = c.read(awaySelectionProvider);
      expect(sel.length, awaySelectionMax);
      expect(
        sel,
        AssetCatalog.all.take(awaySelectionMax).map((a) => a.id),
      );
    });
  });

  group('AwaySelectionNotifier - ekle/kaldir/sira/sinir', () {
    late SharedPreferences prefs;
    late ProviderContainer c;
    late AwaySelectionNotifier n;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      n = c.read(awaySelectionProvider.notifier);
    });

    test('desteklenen varlik eklenebilir; tekrar eklenemez', () {
      expect(c.read(awaySelectionProvider),
          [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId]);

      n.add(AssetCatalog.onsAltinId);
      expect(c.read(awaySelectionProvider).last, AssetCatalog.onsAltinId);

      n.add(AssetCatalog.onsAltinId); // tekrar
      expect(
        c.read(awaySelectionProvider).where((id) => id == AssetCatalog.onsAltinId),
        hasLength(1),
      );
    });

    test('UYDURMA (fake) asset secilemez; katalog disi id yok sayilir', () {
      n.add('sahte-varlik-123');
      n.add('BTC-USDT');
      expect(c.read(awaySelectionProvider),
          [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId],
          reason: 'katalog disi id eklenmemeli');
    });

    test('varlik kaldirilabilir; sadece secim etkilenir', () {
      n.remove(AssetCatalog.gramAltinId);
      expect(c.read(awaySelectionProvider), [AssetCatalog.ceyrekAltinId]);

      n.remove('olmayan-id'); // yok sayilir
      expect(c.read(awaySelectionProvider), [AssetCatalog.ceyrekAltinId]);
    });

    test('bos secim saklanir; yeniden acilista bos KALIR (geri donulebilir)',
        () async {
      n
        ..remove(AssetCatalog.gramAltinId)
        ..remove(AssetCatalog.ceyrekAltinId);
      expect(c.read(awaySelectionProvider), isEmpty);

      await prefs.reload();

      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(awaySelectionProvider), isEmpty);
    });

    test('sira degistirme (yukari/asagi) calisir; sinir asilmaz', () {
      n
        ..add(AssetCatalog.onsAltinId) // [gram, ceyrek, ons]
        ..move(AssetCatalog.onsAltinId, -1);
      expect(c.read(awaySelectionProvider),
          [AssetCatalog.gramAltinId, AssetCatalog.onsAltinId, AssetCatalog.ceyrekAltinId]);

      // Sinir disi: ilk eleman yukari, son eleman asagi gidemez.
      n.move(AssetCatalog.gramAltinId, -1);
      expect(c.read(awaySelectionProvider),
          [AssetCatalog.gramAltinId, AssetCatalog.onsAltinId, AssetCatalog.ceyrekAltinId]);

      n.move(AssetCatalog.ceyrekAltinId, 1);
      expect(c.read(awaySelectionProvider),
          [AssetCatalog.gramAltinId, AssetCatalog.onsAltinId, AssetCatalog.ceyrekAltinId]);
    });

    test('en fazla 6 varlik secilebilir (ust sinir asilmaz)', () {
      for (final a in AssetCatalog.all) {
        n.add(a.id);
      }
      expect(c.read(awaySelectionProvider).length, awaySelectionMax);
      expect(awaySelectionMax, 6);
      expect(
        n.candidates.length,
        AssetCatalog.all.length - awaySelectionMax,
        reason: 'doluyken adaylar kalan katalogdur; ekleme UI\'da pasif olur',
      );
    });

    test('sifirla varsayilana (Gram + Ceyrek) dondurur', () {
      n
        ..remove(AssetCatalog.ceyrekAltinId)
        ..add(AssetCatalog.usdTryId)
        ..reset();
      expect(
        c.read(awaySelectionProvider),
        [AssetCatalog.gramAltinId, AssetCatalog.ceyrekAltinId],
      );
      expect(n.isDefault, isTrue);
    });

    test('adaylar katalogdan gelir; secimdekiler cikarilir', () {
      final candidates = n.candidates;
      expect(candidates, isNotEmpty);
      expect(candidates, isNot(contains(AssetCatalog.gramAltinId)));
      expect(candidates, isNot(contains(AssetCatalog.ceyrekAltinId)));
      expect(
        candidates.every((id) => AssetCatalog.byId(id) != null),
        isTrue,
        reason: 'yalnizca katalog varliklari aday olabilir',
      );
    });
  });

  group('applyAwaySelection (saf fonksiyon)', () {
    AwayChangeItem item(String id) => AwayChangeItem(
          assetId: id,
          name: id,
          symbol: id.toUpperCase(),
          changePercent: 1,
          currentPrice: 2,
          previousPrice: 1,
        );

    test('yalnizca secimdeki varliklar kalir, sira secimi izler', () {
      final items = [item('usd-try'), item('gram-altin'), item('ceyrek-altin')];

      final out = applyAwaySelection(
        items: items,
        selection: const ['ceyrek-altin', 'gram-altin'],
      );

      expect(out.map((i) => i.assetId), ['ceyrek-altin', 'gram-altin']);
    });

    test('secimde olmayan varlik gosterilmez; verisi olmayan secim elenir',
        () {
      final out = applyAwaySelection(
        items: const [],
        selection: const ['gram-altin', 'ceyrek-altin'],
      );
      expect(out, isEmpty, reason: 'uydurma veri uretilmez');
    });

    test('ayni varlik iki kez secimdeyse tek kez gosterilir', () {
      final out = applyAwaySelection(
        items: [item('gram-altin')],
        selection: const ['gram-altin', 'gram-altin'],
      );
      expect(out, hasLength(1));
    });
  });
}
