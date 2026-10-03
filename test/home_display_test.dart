// GOLD v2 - Faz D: Ana Sayfa filtre + siralama (saf fonksiyon).
//
// Kurallar:
//  * Verisi olmayan varlik listeye girmez.
//  * Eksik / NaN deger **her yonde sonda** kalir (0 kabul edilmez).
//  * Esitlikte katalog sirasi korunur; liste ziplamaz.
//  * Varsayilan sira, katalogun kendi sirasidir.
//  * Kategoride varlik yoksa liste bos doner (uydurma veri uretilmez).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/features/home/home_display.dart';
import 'package:shared_preferences/shared_preferences.dart';

AssetDescriptor _a(String id, AssetCategory cat) => AssetDescriptor(
      id: id,
      symbol: id.toUpperCase(),
      name: id,
      category: cat,
      unit: AssetUnit.adet,
      currency: 'TRY',
    );

Quote _q(
  String id, {
  double? price,
  double? change,
  double? changePercent,
  double? bid,
  double? ask,
}) =>
    Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 2, 12, 0),
      price: price,
      change: change,
      changePercent: changePercent,
      bid: bid,
      ask: ask,
    );

final _catalog = <AssetDescriptor>[
  _a('a1', AssetCategory.borsa),
  _a('a2', AssetCategory.borsa),
  _a('g1', AssetCategory.altin),
  _a('g2', AssetCategory.altin),
  _a('s1', AssetCategory.gumus),
  _a('d1', AssetCategory.doviz),
  _a('f1', AssetCategory.fon),
];

const _featured = <String>['g1', 'a1', 'd1', 's1'];

List<String> _run({
  required Map<String, Quote> quotes,
  HomeFilter filter = HomeFilter.onecikanlar,
  HomeSortField sort = HomeSortField.varsayilan,
  bool ascending = true,
  List<String> featured = _featured,
  List<AssetDescriptor>? catalog,
  List<String> watchlist = const <String>[],
}) =>
    applyHomeDisplay(
      featured: featured,
      catalog: catalog ?? _catalog,
      watchlist: watchlist,
      quotes: quotes,
      display: HomeDisplayState(
        filter: filter,
        sort: sort,
        ascending: ascending,
      ),
    );

void main() {
  group('applyHomeDisplay - filtre', () {
    test('varsayilan: onecikanlar sirasi korunur, verisi olmayanlar elenir',
        () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 1),
        'a1': _q('a1', price: 2),
        's1': _q('s1', price: 3),
        // 'd1' verisi yok -> listeye girmez.
      };

      expect(_run(quotes: quotes), <String>['g1', 'a1', 's1']);
    });

    test('tumu: katalog sirasinda, verisi olan varliklar', () {
      final quotes = <String, Quote>{
        'd1': _q('d1', price: 1),
        'a2': _q('a2', price: 2),
        'a1': _q('a1', price: 3),
      };

      expect(
        _run(quotes: quotes, filter: HomeFilter.tumu),
        <String>['a1', 'a2', 'd1'],
      );
    });

    test('kategori filtresi yalniz o kategoridekileri getirir', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 1),
        'g2': _q('g2', price: 2),
        'a1': _q('a1', price: 3),
        's1': _q('s1', price: 4),
        'd1': _q('d1', price: 5),
      };

      expect(
        _run(quotes: quotes, filter: HomeFilter.altin),
        <String>['g1', 'g2'],
      );
      expect(
        _run(quotes: quotes, filter: HomeFilter.borsa),
        <String>['a1'],
      );
      expect(
        _run(quotes: quotes, filter: HomeFilter.gumus),
        <String>['s1'],
      );
      expect(
        _run(quotes: quotes, filter: HomeFilter.doviz),
        <String>['d1'],
      );
    });

    test('fon filtresi GERCEK katalogda bos doner (uydurma veri yok)', () {
      final quotes = <String, Quote>{
        'bist100': _q('bist100', price: 1),
        'gram-altin': _q('gram-altin', price: 1000),
      };

      expect(
        applyHomeDisplay(
          featured: AssetCatalog.featuredIds,
          catalog: AssetCatalog.all,
          watchlist: const <String>[],
          quotes: quotes,
          display: const HomeDisplayState(filter: HomeFilter.fon),
        ),
        isEmpty,
      );
    });

    test('fon kategorisine sahip kayit varsa listelenir', () {
      final quotes = <String, Quote>{'f1': _q('f1', price: 7)};

      expect(
        _run(quotes: quotes, filter: HomeFilter.fon),
        <String>['f1'],
      );
    });

    test('takip filtresi takip listesi sirasini kullanir', () {
      final quotes = <String, Quote>{
        'd1': _q('d1', price: 1),
        'g1': _q('g1', price: 2),
        'a1': _q('a1', price: 3),
      };

      expect(
        _run(
          quotes: quotes,
          filter: HomeFilter.takip,
          watchlist: const <String>['a1', 'g1', 'yok-varlik'],
        ),
        <String>['a1', 'g1'],
      );
    });
  });

  group('applyHomeDisplay - siralama', () {
    test('fiyat azalan: buyukten kucuge', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100),
        'a1': _q('a1', price: 300),
        'd1': _q('d1', price: 200),
        's1': _q('s1', price: 50),
      };

      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.fiyat,
          ascending: false,
        ),
        <String>['a1', 'd1', 'g1', 's1'],
      );
    });

    test('fiyat artan: kucukten buyuge', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100),
        'a1': _q('a1', price: 300),
        'd1': _q('d1', price: 200),
        's1': _q('s1', price: 50),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: true),
        <String>['s1', 'g1', 'd1', 'a1'],
      );
    });

    test('alis ve satis FARKLI siralanir (ayri sutunlar)', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', bid: 10, ask: 40),
        'a1': _q('a1', bid: 30, ask: 11),
        'd1': _q('d1', bid: 20, ask: 22),
        's1': _q('s1', bid: 5, ask: 6),
      };

      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.alis,
          ascending: false,
        ),
        <String>['a1', 'd1', 'g1', 's1'],
      );
      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.satis,
          ascending: false,
        ),
        <String>['g1', 'd1', 'a1', 's1'],
      );
    });

    test('gunluk degisim % artan/azalan', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', changePercent: -1.5),
        'a1': _q('a1', changePercent: 4.0),
        'd1': _q('d1', changePercent: 0.0),
        's1': _q('s1', changePercent: -3.0),
      };

      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.degisimYuzde,
          ascending: false,
        ),
        <String>['a1', 'd1', 'g1', 's1'],
      );
      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.degisimYuzde,
          ascending: true,
        ),
        <String>['s1', 'g1', 'd1', 'a1'],
      );
    });

    test('degisim miktarı yanindaki gercek tutarla siralanir', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100, change: 1),
        'a1': _q('a1', price: 300, change: 3),
        'd1': _q('d1', price: 200, change: 2),
      };

      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.degisimTutar,
          ascending: false,
        ),
        <String>['a1', 'd1', 'g1'],
      );
      expect(
        _run(
          quotes: quotes,
          sort: HomeSortField.degisimTutar,
          ascending: true,
        ),
        <String>['g1', 'd1', 'a1'],
      );
    });
  });

  group('applyHomeDisplay - eksik ve gecerli olmayan degerler', () {
    test('fiyati olmayan varlik ARTAN sirta sonda kalir', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100),
        'a1': _q('a1'), // fiyat yok
        'd1': _q('d1', price: 200),
        's1': _q('s1', price: 50),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: true),
        <String>['s1', 'g1', 'd1', 'a1'],
      );
    });

    test('fiyati olmayan varlik AZALAN sirta da sonda kalir', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100),
        'a1': _q('a1'), // fiyat yok
        'd1': _q('d1', price: 200),
        's1': _q('s1', price: 50),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: false),
        <String>['d1', 'g1', 's1', 'a1'],
      );
    });

    test('NaN deger sonda kabul edilir (0 sayilmaz)', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 100),
        'a1': _q('a1', price: double.nan),
        'd1': _q('d1', price: 200),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: false),
        <String>['d1', 'g1', 'a1'],
      );
      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: true),
        <String>['g1', 'd1', 'a1'],
      );
    });

    test('tum degerler eksikse katalog sirasi korunur', () {
      final quotes = <String, Quote>{
        'g1': _q('g1'),
        'a1': _q('a1'),
        'd1': _q('d1'),
        's1': _q('s1'),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: false),
        _featured,
      );
    });

    test('esit degerlerde katalog sirasi korunur (liste ziplamaz)', () {
      final quotes = <String, Quote>{
        'g1': _q('g1', price: 10),
        'a1': _q('a1', price: 10),
        'd1': _q('d1', price: 10),
        's1': _q('s1', price: 10),
      };

      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: false),
        _featured,
      );
      expect(
        _run(quotes: quotes, sort: HomeSortField.fiyat, ascending: true),
        _featured,
      );
    });
  });

  group('HomeDisplayNotifier', () {
    late ProviderContainer c;

    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('baslangicta varsayilan', () {
      final s = c.read(homeDisplayProvider);
      expect(s.filter, HomeFilter.onecikanlar);
      expect(s.sort, HomeSortField.varsayilan);
      expect(s.ascending, isTrue);
      expect(s.isDefault, isTrue);
    });

    test('setFilter', () {
      c.read(homeDisplayProvider.notifier).setFilter(HomeFilter.altin);
      expect(c.read(homeDisplayProvider).filter, HomeFilter.altin);
      expect(c.read(homeDisplayProvider).isDefault, isFalse);
    });

    test('setSort yon ile', () {
      c
          .read(homeDisplayProvider.notifier)
          .setSort(HomeSortField.fiyat, ascending: false);
      final s = c.read(homeDisplayProvider);
      expect(s.sort, HomeSortField.fiyat);
      expect(s.ascending, isFalse);
    });

    test('hizli kisayollar', () {
      final n = c.read(homeDisplayProvider.notifier);

      n.setQuickRising(rising: true);
      var s = c.read(homeDisplayProvider);
      expect(s.sort, HomeSortField.degisimYuzde);
      expect(s.ascending, isFalse); // en buyuk % basa

      n.setQuickRising(rising: false);
      s = c.read(homeDisplayProvider);
      expect(s.sort, HomeSortField.degisimYuzde);
      expect(s.ascending, isTrue); // en kucuk % (en cok dusen) basa
    });

    test('reset varsayilana doner', () {
      final n = c.read(homeDisplayProvider.notifier);
      n.setFilter(HomeFilter.tumu);
      n.setSort(HomeSortField.satis, ascending: false);
      n.reset();

      final s = c.read(homeDisplayProvider);
      expect(s.filter, HomeFilter.onecikanlar);
      expect(s.sort, HomeSortField.varsayilan);
      expect(s.isDefault, isTrue);
    });
  });

  // Cihaz testinde yakalanan hata: filtre/siralama secimi uygulama her
  // acilista varsayilana donuyordu. Artik SharedPreferences'da saklanir.
  group('HomeDisplayNotifier - kalıcılık', () {
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

    test('secim saklanir ve uygulama yeniden acilinca KORUNUR', () async {
      final c1 = withPrefs();
      addTearDown(c1.dispose);

      c1.read(homeDisplayProvider.notifier)
        ..setFilter(HomeFilter.altin)
        ..setSort(HomeSortField.fiyat, ascending: false);

      // Yazma isleminin magazaya islemesini bekle.
      await prefs.reload();

      // Yeni container = uygulama yeniden baslatildi.
      final c2 = withPrefs();
      addTearDown(c2.dispose);

      final s = c2.read(homeDisplayProvider);
      expect(s.filter, HomeFilter.altin);
      expect(s.sort, HomeSortField.fiyat);
      expect(s.ascending, isFalse);
      expect(s.isDefault, isFalse);
    });

    test('reset varsayilani saklar; sonraki acilista varsayilan gelir',
        () async {
      final c1 = withPrefs();
      addTearDown(c1.dispose);
      c1.read(homeDisplayProvider.notifier).setFilter(HomeFilter.doviz);
      c1.read(homeDisplayProvider.notifier).reset();
      await prefs.reload();

      final c2 = withPrefs();
      addTearDown(c2.dispose);
      expect(c2.read(homeDisplayProvider).isDefault, isTrue);
    });

    test('prefs yoksa uygulama COKMEZ, varsayilan kullanilir', () {
      final c = ProviderContainer(); // override yok
      addTearDown(c.dispose);
      expect(c.read(homeDisplayProvider).isDefault, isTrue);
    });

    test('bozuk/kayit disi deger varsayilana duser (uydurma secim yapilmaz)',
        () async {
      await prefs.setString(HomeDisplayNotifier.prefsKey, 'olmayan|sey|x');
      await prefs.reload();

      final c = withPrefs();
      addTearDown(c.dispose);
      expect(c.read(homeDisplayProvider).isDefault, isTrue);
    });
  });
}
