import 'package:flutter_test/flutter_test.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:gold/domain/news/news_impact.dart';

/// "Neyi etkileyebilir?" / "ilgili haberler" iliski motorunun testleri.
///
/// **Temel kural:** yalnizca *kanit* varsa iliski kurulur:
///  * haberin editoryal kategorisi (guclu kanit),
///  * baslik/ozette **spesifik** varlik adi (orta kanit),
///  * merkez bankasi / ekonmik politika olayi (orta kanit).
///
/// Cift anlamli tek kelimeler ("dolar", "kur", "borsa") **tek basina** iliski
/// kurmaz - aksi halde her haber her varliga baglanir.
void main() {
  NewsItem item({
    required String title,
    NewsCategory category = NewsCategory.ekonomi,
    String? summary,
    int hoursAgo = 1,
  }) {
    return NewsItem(
      id: 'id-$title',
      title: title,
      source: 'Test Kaynak',
      publishedAt: DateTime(2026, 10, 6, 12).subtract(
        Duration(hours: hoursAgo),
      ),
      category: category,
      url: 'https://ornek.com/${title.hashCode}',
      summary: summary,
    );
  }

  group('kanit: haber kategorisi', () {
    test('Altın kategorisi -> ons + gram altın', () {
      final links = NewsImpact.linksFor(item(
        title: 'Altın yükseldi',
        category: NewsCategory.altin,
      ));
      expect(
        links.map((l) => l.assetId),
        containsAll([AssetCatalog.onsAltinId, AssetCatalog.gramAltinId]),
      );
      expect(links.every((l) => l.strength == ImpactStrength.kategori), isTrue);
    });

    test('Döviz kategorisi -> USD/TRY + EUR/TRY', () {
      final links = NewsImpact.linksFor(item(
        title: 'Kur hareketleri',
        category: NewsCategory.doviz,
      ));
      expect(
        links.map((l) => l.assetId),
        containsAll([AssetCatalog.usdTryId, AssetCatalog.eurTryId]),
      );
    });

    test('Şirketler kategorisi tek basına varlik baglamaz', () {
      final links = NewsImpact.linksFor(item(
        title: 'Bir şirket yatırım açıkladı',
        category: NewsCategory.sirketler,
      ));
      expect(links, isEmpty, reason: 'kanit yoksa HİÇBİR ŞEY gosterilmez');
    });
  });

  group('kanit: spesifik varlik adi (baslik/ozet)', () {
    test('Brent adı -> Brent petrol', () {
      final links = NewsImpact.linksFor(item(title: 'Brent petrol geriledi'));
      expect(links.map((l) => l.assetId), contains(AssetCatalog.brentCrudeId));
    });

    test('Bitcoin adı -> Bitcoin (kripto)', () {
      final links = NewsImpact.linksFor(item(title: 'Bitcoin rekor seviyede'));
      expect(links.map((l) => l.assetId), contains(AssetCatalog.bitcoinId));
      expect(
        links.firstWhere((l) => l.assetId == AssetCatalog.bitcoinId).reason,
        contains('Bitcoin'),
      );
    });

    test('Doğalgaz adı -> doğalgaz emtiası', () {
      final links = NewsImpact.linksFor(item(title: 'Doğalgaz fiyatı yükseldi'));
      expect(links.map((l) => l.assetId), contains(AssetCatalog.dogalgazId));
    });

    test('Cift anlamli TEK kelime ("dolar") iliski KURMAZ', () {
      final links = NewsImpact.linksFor(item(
        title: 'Dolar ve altın konuşuldu',
        category: NewsCategory.ekonomi,
      ));
      expect(
        links,
        isEmpty,
        reason: '"dolar" kelimesi tek basina kanit degildir (spam yasagi)',
      );
    });
  });

  group('kanit: merkez bankasi olayi', () {
    test('Fed haberi -> USD/TRY + ons altın + BIST 100', () {
      final links = NewsImpact.linksFor(item(
        title: 'Fed faiz kararını açıkladı',
        category: NewsCategory.merkezBankasi,
      ));
      expect(
        links.map((l) => l.assetId),
        containsAll([
          AssetCatalog.usdTryId,
          AssetCatalog.onsAltinId,
          AssetCatalog.bist100Id,
        ]),
      );
      expect(
        links.every((l) => l.strength == ImpactStrength.sinyal),
        isTrue,
        reason: 'kategori dogrudan ilgili degil, sinyal ile baglanir',
      );
    });

    test('Merkez Bankası haberi -> ayni kanal', () {
      final links = NewsImpact.linksFor(item(
        title: 'Merkez Bankası toplantı tutanakları',
        category: NewsCategory.merkezBankasi,
      ));
      expect(links.map((l) => l.assetId), contains(AssetCatalog.usdTryId));
    });
  });

  group('ters yon: varlik -> haberler', () {
    test('varlikla iliskili haberler doner', () {
      final items = [
        item(title: 'Altın yükseldi', category: NewsCategory.altin),
        item(title: 'Bitcoin rekor seviyede'),
        item(title: 'Hava durumu güzel', category: NewsCategory.ekonomi),
      ];
      final gold = NewsImpact.newsForAsset(items, AssetCatalog.onsAltinId);
      expect(gold, hasLength(1));
      expect(gold.single.title, 'Altın yükseldi');
    });

    test('iliskisiz haber cikti olarak doner', () {
      final items = [item(title: 'Hava durumu güzel')];
      expect(NewsImpact.newsForAsset(items, AssetCatalog.bist100Id), isEmpty);
    });

    test('sonuc en yeni once siralanir', () {
      final items = [
        item(title: 'Altın haberi eski', category: NewsCategory.altin, hoursAgo: 40),
        item(title: 'Altın haberi yeni', category: NewsCategory.altin, hoursAgo: 1),
      ];
      final out = NewsImpact.newsForAsset(items, AssetCatalog.onsAltinId);
      expect(out.first.title, 'Altın haberi yeni');
    });
  });

  group('dostluk (koruma)', () {
    test('tüm varlik id\'leri katalogda var', () {
      final sample = [
        item(title: 'Altın ve Bitcoin', category: NewsCategory.altin),
        item(title: 'Fed ve doğalgaz'),
      ];
      for (final i in sample) {
        for (final l in NewsImpact.linksFor(i)) {
          expect(AssetCatalog.byId(l.assetId), isNotNull, reason: l.assetId);
          expect(l.reason, isNotEmpty);
        }
      }
    });

    test('assetIdsFor ve linksFor ayni sonucu verir', () {
      final i = item(title: 'Brent petrol', category: NewsCategory.altin);
      expect(
        NewsImpact.assetIdsFor(i).toSet(),
        NewsImpact.linksFor(i).map((l) => l.assetId).toSet(),
      );
    });
  });
}
