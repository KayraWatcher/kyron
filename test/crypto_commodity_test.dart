import 'package:flutter_test/flutter_test.dart';
import 'package:gold/data/canlidoviz/canlidoviz_protocol.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';

/// 1.2.0 kapsami: kripto (Bitcoin/Ethereum) + emtia genislemesi.
///
/// Tüm cid / abonelik kodlari **canli API dogrulamasiyla** alinmistir
/// (WebSocket tik degeri + history DAILY kapanisi + liste sayfasi DOM).
void main() {
  group('KRIPTO kategorisi', () {
    test('kategori katalogda ve etiketi "Kripto"', () {
      expect(AssetCategory.values.map((c) => c.label), contains('Kripto'));
      expect(AssetCatalog.byCategory(AssetCategory.kripto), isNotEmpty);
    });

    test('Bitcoin: parite acikca BTC/USD, canli + history + yedek', () {
      final b = AssetCatalog.bitcoin;
      expect(b.id, 'bitcoin');
      expect(b.symbol, 'BTC');
      expect(b.category, AssetCategory.kripto);
      expect(b.currency, 'USD');
      expect(b.unit, AssetUnit.adet);
      expect(
        b.description,
        contains('BTC/USD'),
        reason: 'kullanici hangi paritenin gosterildigini bilmelidir',
      );
      expect(
        b.providerSymbol,
        'BTC-USD',
        reason: 'yedek kaynak (dogrulandi: Yahoo BTC-USD 85.480 ~ CanlıDöviz 85.478)',
      );
      // CanlıDöviz: cid + abonelik kodu
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.bitcoinId), 62);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.bitcoinId),
        'BTC',
      );
      expect(
        CanlidovizProtocol.streamAssetIds,
        contains(AssetCatalog.bitcoinId),
        reason: 'BTC akisa abone olunur (canli tik dogrulandi)',
      );
    });

    test('Ethereum: ETH/USD + cid 52 + kod ETH', () {
      final e = AssetCatalog.ethereum;
      expect(e.symbol, 'ETH');
      expect(e.category, AssetCategory.kripto);
      expect(e.currency, 'USD');
      expect(e.providerSymbol, 'ETH-USD');
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.ethereumId), 52);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.ethereumId),
        'ETH',
      );
    });

    test('kripto kategorisi genislecebilir (varlik listesi acik)', () {
      // Kategori tek bir varliga bagli degildir: liste katalogda durur,
      // yeni kripto ayni kalip ile eklenebilir.
      final ids = AssetCatalog.byCategory(AssetCategory.kripto)
          .map((a) => a.id)
          .toList();
      expect(ids, contains(AssetCatalog.bitcoinId));
      expect(ids.toSet().length, ids.length, reason: 'id tekrari olmamali');
    });
  });

  group('EMTIA genislemesi', () {
    test('Paladyum: XPD/USD, canli; yedek kaynak UYDURULMAZ', () {
      final p = AssetCatalog.paladyum;
      expect(p.id, 'paladyum');
      expect(p.symbol, 'XPD/USD');
      expect(p.category, AssetCategory.emtia);
      expect(p.unit, AssetUnit.ons);
      expect(p.currency, 'USD');
      expect(
        p.providerSymbol,
        isNull,
        reason: 'paladyum icin dogrulanmis yedek kaynak yok; '
            'uydurma sembol verilmemeli',
      );
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.paladyumId), 269);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.paladyumId),
        'XPD/USD',
      );
    });

    test('Bakır: USD/libre + COPPER kodu + HG=F yedeği', () {
      final b = AssetCatalog.bakir;
      expect(b.symbol, 'COPPER');
      expect(b.unit, AssetUnit.libre);
      expect(b.currency, 'USD');
      expect(b.providerSymbol, 'HG=F');
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.bakirId), 1056);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.bakirId),
        'COPPER',
      );
    });

    test('Doğalgaz: USD/MMBtu + NGAS kodu + NG=F yedeği', () {
      final g = AssetCatalog.dogalgaz;
      expect(g.symbol, 'NGAS');
      expect(g.unit, AssetUnit.mmbtu);
      expect(g.currency, 'USD');
      expect(g.providerSymbol, 'NG=F');
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.dogalgazId), 1064);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.dogalgazId),
        'NGAS',
      );
    });

    test('Platin (Gram): TRY gram + GRPLTN kodu', () {
      final g = AssetCatalog.platinGram;
      expect(g.symbol, 'GRPLTN');
      expect(g.unit, AssetUnit.gram);
      expect(g.currency, 'TRY');
      expect(CanlidovizProtocol.assetToItemId(AssetCatalog.platinGramId), 1012);
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.platinGramId),
        'GRPLTN',
      );
    });

    test('emtia kategorisi 7 varlik (petrol + metaller + enerji)', () {
      final emtia = AssetCatalog.byCategory(AssetCategory.emtia);
      expect(emtia, hasLength(7));
      expect(emtia.map((a) => a.id), contains(AssetCatalog.paladyumId));
      expect(emtia.map((a) => a.id), contains(AssetCatalog.bakirId));
      expect(emtia.map((a) => a.id), contains(AssetCatalog.dogalgazId));
    });
  });

  group('katalog butunlugu', () {
    test('id ve sembol benzersiz', () {
      final ids = AssetCatalog.all.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'id tekrari olmamali');
      // Sembol tekrarsi arama/sorgu karisir.
      final symbols = AssetCatalog.all.map((a) => a.symbol).toList();
      expect(symbols.toSet(), hasLength(symbols.length));
    });

    test('her varligin aciklamasi var (kullanici ne gordugunu bilir)', () {
      for (final a in AssetCatalog.all) {
        expect(a.description, isNotNull, reason: '${a.id} aciklamasiz');
        expect(a.description!.trim(), isNotEmpty);
      }
    });

    test('tum katalog varliklarinin CanlıDöviz cid eslemesi var', () {
      for (final a in AssetCatalog.all) {
        expect(CanlidovizProtocol.assetToItemId(a.id), isNotNull, reason: a.id);
      }
    });
  });
}
