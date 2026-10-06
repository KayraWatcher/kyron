import 'package:flutter_test/flutter_test.dart';

import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/asset.dart';

void main() {
  group('AssetCatalog providerSymbol mappings', () {
    test('onsAltin providerSymbol is XAU (Gold API spot)', () {
      final asset = AssetCatalog.byId(AssetCatalog.onsAltinId);
      expect(asset, isNotNull);
      expect(asset!.providerSymbol, 'XAU');
      expect(asset.symbol, 'XAUUSD');
      expect(asset.currency, 'USD');
      expect(asset.unit, AssetUnit.ons);
      expect(asset.isCalculated, isFalse);
    });

    test('onsGumus providerSymbol is XAG (Gold API spot)', () {
      final asset = AssetCatalog.byId(AssetCatalog.onsGumusId);
      expect(asset, isNotNull);
      expect(asset!.providerSymbol, 'XAG');
      expect(asset.symbol, 'XAGUSD');
      expect(asset.currency, 'USD');
      expect(asset.unit, AssetUnit.ons);
      expect(asset.isCalculated, isFalse);
    });

    test('gramAltin calculated formula unchanged', () {
      final asset = AssetCatalog.byId(AssetCatalog.gramAltinId);
      expect(asset, isNotNull);
      expect(asset!.isCalculated, isTrue);
      expect(asset.parentIds, [AssetCatalog.onsAltinId, AssetCatalog.usdTryId]);
    });

    test('gramGumus calculated formula unchanged', () {
      final asset = AssetCatalog.byId(AssetCatalog.gramGumusId);
      expect(asset, isNotNull);
      expect(asset!.isCalculated, isTrue);
      expect(asset.parentIds, [AssetCatalog.onsGumusId, AssetCatalog.usdTryId]);
    });

    test('FX assets still have Yahoo providerSymbol for %change', () {
      expect(AssetCatalog.byId(AssetCatalog.usdTryId)!.providerSymbol, 'USDTRY=X');
      expect(AssetCatalog.byId(AssetCatalog.eurTryId)!.providerSymbol, 'EURTRY=X');
      expect(AssetCatalog.byId(AssetCatalog.gbpTryId)!.providerSymbol, 'GBPTRY=X');
      expect(AssetCatalog.byId(AssetCatalog.chfTryId)!.providerSymbol, 'CHFTRY=X');
      expect(AssetCatalog.byId(AssetCatalog.jpyTryId)!.providerSymbol, 'JPYTRY=X');
    });

    test('WTI/Brent still use Yahoo futures symbols', () {
      expect(AssetCatalog.byId(AssetCatalog.wtiCrudeId)!.providerSymbol, 'CL=F');
      expect(AssetCatalog.byId(AssetCatalog.brentCrudeId)!.providerSymbol, 'BZ=F');
    });

    test('BIST still uses Yahoo symbols', () {
      expect(AssetCatalog.byId(AssetCatalog.bist100Id)!.providerSymbol, 'XU100.IS');
      expect(AssetCatalog.byId(AssetCatalog.bist30Id)!.providerSymbol, 'XU030.IS');
    });
  });
}