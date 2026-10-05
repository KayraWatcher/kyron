import 'asset.dart';

/// Uygulama genelindeki tum varliklarin tek dogruluk kaynagi.
///
/// Semboller gercek kaynaklarla eslestirilir:
///   * Yahoo Finance  -> `<SEMBOL>.IS` (BIST), `GC=F`/`SI=F` (ons metal),
///     `USDTRY=X` (doviz paritesi - yalnizca degisim orani icin)
///   * TCMB           -> `USD`, `EUR`, `GBP` (serbest piyasa)
///
/// **Not (yasam testi ile dogrulandi):** Yahoo `XAUUSD=X` / `XAGUSD=X`
/// sembollerini kaldirilmistir (404). Ons altin icin `GC=F`, ons gumus icin
/// `SI=F` kullanilir - ikisi de canli olarak test edilmistir.
abstract final class AssetCatalog {
  static const String gramAltinId = 'gram-altin';
  static const String ceyrekAltinId = 'ceyrek-altin';
  static const String yarimAltinId = 'yarim-altin';
  static const String tamAltinId = 'tam-altin';
  static const String cumhuriyetAltinId = 'cumhuriyet-altin';
  static const String ataAltinId = 'ata-altin';
  static const String bilezik22Id = 'bilezik-22';
  static const String onsAltinId = 'ons-altin';
  static const String ayar14AltinId = '14-ayar-altin';
  static const String ayar18AltinId = '18-ayar-altin';
  static const String resatAltinId = 'resat-altin';
  static const String gramGumusId = 'gram-gumus';
  static const String onsGumusId = 'ons-gumus';
  static const String usdTryId = 'usd-try';
  static const String eurTryId = 'eur-try';
  static const String gbpTryId = 'gbp-try';
  static const String chfTryId = 'chf-try';
  static const String jpyTryId = 'jpy-try';
  static const String bist100Id = 'bist-100';
  static const String bist30Id = 'bist-30';

  // ---------------------------------------------------------------------------
  // ALTIN
  // ---------------------------------------------------------------------------

  /// Ons altin - dogrudan kaynak verisi (Yahoo: GC=F, COMEX vadeli).
  static const AssetDescriptor onsAltin = AssetDescriptor(
    id: onsAltinId,
    symbol: 'XAUUSD',
    name: 'Ons Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.ons,
    currency: 'USD',
    providerSymbol: 'GC=F',
    description: 'Uluslararası ons altın fiyatı (USD/ons).',
  );

  /// Gram altin = Ons altin x USD/TRY / 31.1035 -> HESAPLANAN.
  static const AssetDescriptor gramAltin = AssetDescriptor(
    id: gramAltinId,
    symbol: 'GRAMALTIN',
    name: 'Gram Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [onsAltinId, usdTryId],
    description: 'Ons altın ve USD/TRY kullanılarak hesaplanır: ons × kur ÷ 31,1035.',
  );

  /// Turk piyasasindaki standart ayarlar (24 ayar gram altin esas alinir).
  static const AssetDescriptor ceyrekAltin = AssetDescriptor(
    id: ceyrekAltinId,
    symbol: 'CEYREK',
    name: 'Çeyrek Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.adet,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: 'Yeni çeyrek: 1,75 g, eski çeyrek: 1,80 g saf altın karşılığı.',
  );

  static const AssetDescriptor yarimAltin = AssetDescriptor(
    id: yarimAltinId,
    symbol: 'YARIM',
    name: 'Yarım Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.adet,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: 'Yeni yarım: 3,50 g, eski yarım: 3,60 g saf altın karşılığı.',
  );

  static const AssetDescriptor tamAltin = AssetDescriptor(
    id: tamAltinId,
    symbol: 'TAM',
    name: 'Tam Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.adet,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: 'Yeni tam: 7,00 g, eski tam: 7,20 g saf altın karşılığı.',
  );

  static const AssetDescriptor cumhuriyetAltin = AssetDescriptor(
    id: cumhuriyetAltinId,
    symbol: 'CUMHURIYET',
    name: 'Cumhuriyet Altını',
    category: AssetCategory.altin,
    unit: AssetUnit.adet,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: '7,216 g saf altın karşılığı (darphane).',
  );

  static const AssetDescriptor ataAltin = AssetDescriptor(
    id: ataAltinId,
    symbol: 'ATA',
    name: 'Ata Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.adet,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: '7,216 g ağırlığında, Cumhuriyet altını ile aynı içerik.',
  );

  static const AssetDescriptor bilezik22 = AssetDescriptor(
    id: bilezik22Id,
    symbol: 'BILEZIK22',
    name: '22 Ayar Bilezik',
    category: AssetCategory.altin,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [gramAltinId],
    description: '22 ayar = 0,916 saflık; gram altının 0,916 katı.',
  );

  static const AssetDescriptor ayar14Altin = AssetDescriptor(
    id: ayar14AltinId,
    symbol: 'AYAR14',
    name: '14 Ayar Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: false,
    parentIds: [],
    description: '14 ayar altın (585 saflık) gram cinsinden.',
  );

  static const AssetDescriptor ayar18Altin = AssetDescriptor(
    id: ayar18AltinId,
    symbol: 'AYAR18',
    name: '18 Ayar Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: false,
    parentIds: [],
    description: '18 ayar altın (750 saflık) gram cinsinden.',
  );

  static const AssetDescriptor resatAltin = AssetDescriptor(
    id: resatAltinId,
    symbol: 'RESAT',
    name: 'Reşat Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: false,
    parentIds: [],
    description: 'Reşat altını (22 ayar, 7.216 g) gram cinsinden.',
  );

  // ---------------------------------------------------------------------------
  // GUMUS
  // ---------------------------------------------------------------------------

  /// Ons gumus - dogrudan kaynak verisi (Yahoo: SI=F, COMEX vadeli).
  static const AssetDescriptor onsGumus = AssetDescriptor(
    id: onsGumusId,
    symbol: 'XAGUSD',
    name: 'Ons Gümüş',
    category: AssetCategory.gumus,
    unit: AssetUnit.ons,
    currency: 'USD',
    providerSymbol: 'SI=F',
    description: 'Uluslararası ons gümüş fiyatı (USD/ons).',
  );

  static const AssetDescriptor gramGumus = AssetDescriptor(
    id: gramGumusId,
    symbol: 'GRAMGUMUS',
    name: 'Gram Gümüş',
    category: AssetCategory.gumus,
    unit: AssetUnit.gram,
    currency: 'TRY',
    isCalculated: true,
    parentIds: [onsGumusId, usdTryId],
    description: 'Ons gümüş ve USD/TRY kullanılarak hesaplanır: ons × kur ÷ 31,1035.',
  );

  // ---------------------------------------------------------------------------
  // DOVIZ  (TCMB serbest piyasa - dogrudan kaynak)
  // ---------------------------------------------------------------------------

  // `providerSymbol`: Yahoo parite sembolu - yalnizca **degisim orani** icin
  // kullanilir (fiyat TCMB'den gelir). Fiyat istegi bu sembolle yapilmaz.
  static const AssetDescriptor usdTry = AssetDescriptor(
    id: usdTryId,
    symbol: 'USD',
    providerSymbol: 'USDTRY=X',
    name: 'Dolar / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'TCMB serbest piyasa USD/TRY alış-satış kuru.',
  );

  static const AssetDescriptor eurTry = AssetDescriptor(
    id: eurTryId,
    symbol: 'EUR',
    providerSymbol: 'EURTRY=X',
    name: 'Euro / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'TCMB serbest piyasa EUR/TRY alış-satış kuru.',
  );

  static const AssetDescriptor gbpTry = AssetDescriptor(
    id: gbpTryId,
    symbol: 'GBP',
    providerSymbol: 'GBPTRY=X',
    name: 'Sterlin / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'TCMB serbest piyasa GBP/TRY alış-satış kuru.',
  );

  static const AssetDescriptor chfTry = AssetDescriptor(
    id: chfTryId,
    symbol: 'CHF',
    providerSymbol: 'CHFTRY=X',
    name: 'İsviçre Frangı / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'TCMB serbest piyasa CHF/TRY alış-satış kuru.',
  );

  static const AssetDescriptor jpyTry = AssetDescriptor(
    id: jpyTryId,
    symbol: 'JPY',
    providerSymbol: 'JPYTRY=X',
    name: 'Japon Yeni / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'TCMB serbest piyasa JPY/TRY alış-satış kuru (100 JPY).',
  );

  // ---------------------------------------------------------------------------
  // BORSA  (Yahoo Finance BIST)
  // ---------------------------------------------------------------------------

  static const AssetDescriptor bist100 = AssetDescriptor(
    id: bist100Id,
    symbol: 'XU100',
    name: 'BIST 100',
    category: AssetCategory.borsa,
    unit: AssetUnit.puan,
    currency: 'TRY',
    providerSymbol: 'XU100.IS',
    description: 'Borsa İstanbul 100 endeksi.',
  );

  static const AssetDescriptor bist30 = AssetDescriptor(
    id: bist30Id,
    symbol: 'XU030',
    name: 'BIST 30',
    category: AssetCategory.borsa,
    unit: AssetUnit.puan,
    currency: 'TRY',
    providerSymbol: 'XU030.IS',
    description: 'Borsa İstanbul 30 (bankacılık-dışı likit) endeksi.',
  );

  // ---------------------------------------------------------------------------
  // KAYITLAR
  // ---------------------------------------------------------------------------

  static const List<AssetDescriptor> all = [
    // Borsa
    bist100,
    bist30,
    // Altın
    gramAltin,
    ceyrekAltin,
    yarimAltin,
    tamAltin,
    cumhuriyetAltin,
    ataAltin,
    bilezik22,
    ayar14Altin,
    ayar18Altin,
    resatAltin,
    onsAltin,
    // Gümüş
    gramGumus,
    onsGumus,
    // Döviz
    usdTry,
    eurTry,
    gbpTry,
    chfTry,
    jpyTry,
  ];

  static final Map<String, AssetDescriptor> _byId = {
    for (final a in all) a.id: a,
  };

  static AssetDescriptor? byId(String id) => _byId[id];

  /// Bulunamazsa null dondurur; asla sahte varlik uretmez.
  static AssetDescriptor? bySymbol(String symbol) {
    for (final a in all) {
      if (a.symbol == symbol) return a;
    }
    return null;
  }

  static List<AssetDescriptor> byCategory(AssetCategory c) =>
      all.where((a) => a.category == c).toList();

  /// Ana sayfada gosterilecek one cikan varliklar.
  static const List<String> featuredIds = [
    bist100Id,
    bist30Id,
    gramAltinId,
    ceyrekAltinId,
    ayar14AltinId,
    ayar18AltinId,
    resatAltinId,
    gramGumusId,
    usdTryId,
    eurTryId,
  ];
}
