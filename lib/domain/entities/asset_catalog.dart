import 'asset.dart';

/// Uygulama genelindeki tum varliklarin tek dogruluk kaynagi.
///
/// Semboller gercek kaynaklarla eslestirilir:
///   * CanlıDöviz   -> kod/cid eslemesi `CanlidovizProtocol`'te (anlik akis
///     + tarihsel mum; ornek `GA`/`XAU/USD`/`XBRUSD`/`COIL`/`DXY`)
///   * Gold API       -> `XAU` / `XAG` (Ons Altin / Ons Gumus **SPOT fiyat**)
///   * Yahoo Finance  -> `<SEMBOL>.IS` (BIST), `GC=F`/`SI=F` (ons metal
///     **grafik/OHLC serisi**), `CL=F`/`BZ=F` (ham petrol - WTI/Brent),
///     `USDTRY=X` (doviz paritesi - yalnizca degisim orani icin)
///   * TCMB           -> `USD`, `EUR`, `GBP` (serbest piyasa)
///
/// **Not (yasam testi ile dogrulandi, 2026-10-06):** Yahoo `XAUUSD=X` /
/// `XAGUSD=X` kaldirilmistir (HTTP 404) ve `.../chart/XAU` ile `.../chart/XAG`
/// **kalici olarak HTTP 404** dondurur ("No data found, symbol may be
/// delisted"). Bu yuzden **fiyat sembolu ile grafik sembolu ayridir**:
///   * Fiyat  -> `providerSymbol`     = `XAU` / `XAG` (Gold API spot)
///   * Grafik -> `chartProviderSymbol` = `GC=F` / `SI=F` (Yahoo OHLC)
///
/// `GC=F` / `SI=F` **futures** sembolleridir: ekrandaki fiyat etiketi bunlarla
/// degil, Gold API spot verisiyle uretilir; bu semboller yalnizca tarihsel mum
/// serisini besler.
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
  static const String wtiCrudeId = 'wti-crude';
  static const String brentCrudeId = 'brent-crude';
  // Genisletme (2026-10-06 CanliDoviz kapsam testi ile eklendi):
  static const String cadTryId = 'cad-try';
  static const String audTryId = 'aud-try';
  static const String cnyTryId = 'cny-try';
  static const String dxyId = 'dxy';
  static const String sp500Id = 'sp-500';
  static const String bist50Id = 'bist-50';
  static const String platinId = 'platin';
  // 1.2.0 emtia + kripto genislemesi (canli API dogrulamasi 2026-10-06):
  static const String paladyumId = 'paladyum';
  static const String bakirId = 'bakir';
  static const String dogalgazId = 'dogalgaz';
  static const String platinGramId = 'platin-gram';
  static const String bitcoinId = 'bitcoin';
  static const String ethereumId = 'ethereum';

  // ---------------------------------------------------------------------------
  // ALTIN
  // ---------------------------------------------------------------------------

  /// Ons altin - dogrudan kaynak verisi (Gold API: XAU, LBMA spot).
  static const AssetDescriptor onsAltin = AssetDescriptor(
    id: onsAltinId,
    symbol: 'XAUUSD',
    name: 'Ons Altın',
    category: AssetCategory.altin,
    unit: AssetUnit.ons,
    currency: 'USD',
    providerSymbol: 'XAU',
    // Grafik sembolu FARKLIDIR: Yahoo /v8/finance/chart/XAU ve /XAG kalici
    // olarak HTTP 404 ("No data found, symbol may be delisted") dondurur;
    // /GC=F ve /SI=F ise HTTP 200'dur. Fiyat (current price) yine Gold API
    // SPOT XAU/XAG'ten gelir - bu sembol yalnizca OHLC serisi icindir.
    chartProviderSymbol: 'GC=F',
    description: 'Uluslararası ons altın SPOT fiyatı (USD/troy oz).',
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

  /// Ons gumus - dogrudan kaynak verisi (Gold API: XAG, LBMA spot).
  static const AssetDescriptor onsGumus = AssetDescriptor(
    id: onsGumusId,
    symbol: 'XAGUSD',
    name: 'Ons Gümüş',
    category: AssetCategory.gumus,
    unit: AssetUnit.ons,
    currency: 'USD',
    providerSymbol: 'XAG',
    // Fiyat SPOT XAG (Gold API); grafik serisi Yahoo /SI=F (200) - /XAG 404.
    chartProviderSymbol: 'SI=F',
    description: 'Uluslararası ons gümüş SPOT fiyatı (USD/troy oz).',
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
    description: 'Serbest piyasa USD/TRY alış-satış kuru.',
  );

  static const AssetDescriptor eurTry = AssetDescriptor(
    id: eurTryId,
    symbol: 'EUR',
    providerSymbol: 'EURTRY=X',
    name: 'Euro / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa EUR/TRY alış-satış kuru.',
  );

  static const AssetDescriptor gbpTry = AssetDescriptor(
    id: gbpTryId,
    symbol: 'GBP',
    providerSymbol: 'GBPTRY=X',
    name: 'Sterlin / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa GBP/TRY alış-satış kuru.',
  );

  static const AssetDescriptor chfTry = AssetDescriptor(
    id: chfTryId,
    symbol: 'CHF',
    providerSymbol: 'CHFTRY=X',
    name: 'İsviçre Frangı / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa CHF/TRY alış-satış kuru.',
  );

  static const AssetDescriptor jpyTry = AssetDescriptor(
    id: jpyTryId,
    symbol: 'JPY',
    providerSymbol: 'JPYTRY=X',
    name: 'Japon Yeni / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa JPY/TRY alış-satış kuru (100 JPY).',
  );

  static const AssetDescriptor cadTry = AssetDescriptor(
    id: cadTryId,
    symbol: 'CAD',
    providerSymbol: 'CADTRY=X',
    name: 'Kanada Doları / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa CAD/TRY alış-satış kuru.',
  );

  static const AssetDescriptor audTry = AssetDescriptor(
    id: audTryId,
    symbol: 'AUD',
    providerSymbol: 'AUDTRY=X',
    name: 'Avustralya Doları / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa AUD/TRY alış-satış kuru.',
  );

  static const AssetDescriptor cnyTry = AssetDescriptor(
    id: cnyTryId,
    symbol: 'CNY',
    // Yahoo `CNYTRY=X` sembolu 404 (yasam testi 2026-10-06): TCMB yedek
    // kaynakli degisim yuzdesi bu sembolle alinamaz; CanlıDöviz akisi ve
    // previousClose kapanisi degisimi karsilar. Grafik TCMB'den degil
    // CanlıDöviz history'den gelir (supportsCandles).
    providerSymbol: 'CNYTRY=X',
    name: 'Çin Yuanı / Türk Lirası',
    category: AssetCategory.doviz,
    unit: AssetUnit.para,
    currency: 'TRY',
    description: 'Serbest piyasa CNY/TRY alış-satış kuru.',
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

  static const AssetDescriptor bist50 = AssetDescriptor(
    id: bist50Id,
    symbol: 'XU050',
    name: 'BIST 50',
    category: AssetCategory.borsa,
    unit: AssetUnit.puan,
    currency: 'TRY',
    providerSymbol: 'XU050.IS',
    description: 'Borsa İstanbul 50 endeksi.',
  );

  /// Dolar endeksi (DXY) - CanlıDöviz `DXY` (cid 846), yedek Yahoo.
  static const AssetDescriptor dxy = AssetDescriptor(
    id: dxyId,
    symbol: 'DXY',
    providerSymbol: 'DX-Y.NYB',
    name: 'Dolar Endeksi (DXY)',
    category: AssetCategory.borsa,
    unit: AssetUnit.puan,
    currency: 'USD',
    description: 'Doların başlıca para birimlerine karşı gücünü ölçen endeks.',
  );

  /// S&P 500 - CanlıDöviz `SPX` (cid 1015), yedek Yahoo `^GSPC`.
  static const AssetDescriptor sp500 = AssetDescriptor(
    id: sp500Id,
    symbol: 'SPX',
    providerSymbol: '^GSPC',
    name: 'S&P 500 Endeksi',
    category: AssetCategory.borsa,
    unit: AssetUnit.puan,
    currency: 'USD',
    description: 'ABD\'nin en büyük 500 şirketini kapsayan endeks.',
  );

  // ---------------------------------------------------------------------------
  // EMTIA  (Yahoo Energy futures - dogrudan kaynak)
  // ---------------------------------------------------------------------------

  /// Ham petrol (WTI) - dogrudan kaynak verisi (Yahoo: CL=F, NYMEX vadeli).
  ///
  /// **Dogrulama (yasam testi):** `CL=F` -> "Crude Oil Nov 26", USD,
  /// `America/New_York` oturum bilgisi ile birlikte gelir; boylece
  /// acik/kapali durumu [DataFreshness] olarak **veriden okunur**.
  static const AssetDescriptor wtiCrude = AssetDescriptor(
    id: wtiCrudeId,
    symbol: 'WTI',
    name: 'Ham Petrol (WTI)',
    category: AssetCategory.emtia,
    unit: AssetUnit.varil,
    currency: 'USD',
    providerSymbol: 'CL=F',
    description: 'ABD ham petrol vadeli fiyatı - NYMEX WTI (USD/varil).',
  );

  /// Brent ham petrol - dogrudan kaynak verisi (Yahoo: BZ=F, ICE vadeli).
  ///
  /// **Dogrulama (yasam testi):** `BZ=F` -> "Brent Crude Oil Last Day
  /// Financial", USD, `America/New_York` oturum bilgisi ile gelir.
  static const AssetDescriptor brentCrude = AssetDescriptor(
    id: brentCrudeId,
    symbol: 'BRENT',
    name: 'Brent Petrol',
    category: AssetCategory.emtia,
    unit: AssetUnit.varil,
    currency: 'USD',
    providerSymbol: 'BZ=F',
    description: 'Brent ham petrol vadeli fiyatı - ICE (USD/varil).',
  );

  /// Platin SPOT (XPT/USD) - CanlıDöviz `XPT/USD` (cid 268), yedek Yahoo
  /// `PL=F` (yasam testi: PL=F 1718 ~ CanlıDöviz 1713 - %0,3 futures
  /// baz farki, ons-altin/GC=F ile ayni kabul edilen semantik).
  static const AssetDescriptor platin = AssetDescriptor(
    id: platinId,
    symbol: 'XPT/USD',
    providerSymbol: 'PL=F',
    name: 'Platin (Spot)',
    category: AssetCategory.emtia,
    unit: AssetUnit.ons,
    currency: 'USD',
    description: 'Uluslararası platin SPOT fiyatı (USD/troy oz).',
  );

  /// Paladyum SPOT (XPD/USD) - CanlıDöviz `XPD/USD` (cid 269).
  ///
  /// Yedek kaynak **yoktur**: piyasa saglayicilarinda paladyum vadeli
  /// sembolu bulunmuyor (dogrulama 2026-10-06). Bu yuzden fiyat yalnizca
  /// CanlıDöviz akışından gelir; akış yoksa **deger uydurulmaz**, onceki
  /// gecerli deger gosterilir ya da veri bos kalir.
  static const AssetDescriptor paladyum = AssetDescriptor(
    id: paladyumId,
    symbol: 'XPD/USD',
    name: 'Paladyum (Spot)',
    category: AssetCategory.emtia,
    unit: AssetUnit.ons,
    currency: 'USD',
    description: 'Uluslararası paladyum SPOT fiyatı (USD/troy oz).',
  );

  /// Bakır (CanlıDöviz `COPPER`, cid 1056; USD/libre).
  ///
  /// Yedek kaynak Yahoo `HG=F` (dogrulama: 6,662 ~ CanlıDöviz kapanış 6,64).
  /// Bakır akışı yalnız borsa saatlerinde canlıdır (kapalıyken tik gelmez).
  static const AssetDescriptor bakir = AssetDescriptor(
    id: bakirId,
    symbol: 'COPPER',
    providerSymbol: 'HG=F',
    name: 'Bakır',
    category: AssetCategory.emtia,
    unit: AssetUnit.libre,
    currency: 'USD',
    description: 'Bakır fiyatı (USD/libre).',
  );

  /// Doğalgaz (CanlıDöviz `NGAS`, cid 1064; USD/MMBtu).
  ///
  /// Yedek kaynak Yahoo `NG=F` (dogrulama: 3,076 ~ CanlıDöviz kapanış 3,074).
  static const AssetDescriptor dogalgaz = AssetDescriptor(
    id: dogalgazId,
    symbol: 'NGAS',
    providerSymbol: 'NG=F',
    name: 'Doğalgaz',
    category: AssetCategory.emtia,
    unit: AssetUnit.mmbtu,
    currency: 'USD',
    description: 'Doğalgaz fiyatı (USD/MMBtu).',
  );

  /// Platin gram (CanlıDöviz `GRPLTN`, cid 1012) - **TRY** gram fiyatı.
  ///
  /// Gram fiyatinin yedegi yoktur (spot ons fiyatinin gram karşılığı
  /// uydurulmaz); yalnız CanlıDöviz akışı ve geçmişi kullanılır.
  static const AssetDescriptor platinGram = AssetDescriptor(
    id: platinGramId,
    symbol: 'GRPLTN',
    name: 'Platin (Gram)',
    category: AssetCategory.emtia,
    unit: AssetUnit.gram,
    currency: 'TRY',
    description: 'Platin gram fiyatı (TRY).',
  );

  // ---------------------------------------------------------------------------
  // KRIPTO  (1.2.0 - CanlıDöviz akışı + history)
  //
  // Kripto **kategorisi** geniş tutulmuştur: Bitcoin ve Ethereum dışında
  // başka kriptolar da aynı kalıpla (cid + abonelik kodu) eklenebilir.
  // ---------------------------------------------------------------------------

  /// Bitcoin (CanlıDöviz `BTC`, cid 62) - parite **BTC/USD**.
  static const AssetDescriptor bitcoin = AssetDescriptor(
    id: bitcoinId,
    symbol: 'BTC',
    providerSymbol: 'BTC-USD',
    name: 'Bitcoin',
    category: AssetCategory.kripto,
    unit: AssetUnit.adet,
    currency: 'USD',
    description: 'Bitcoin fiyatı (BTC/USD).',
  );

  /// Ethereum (CanlıDöviz `ETH`, cid 52) - parite **ETH/USD**.
  static const AssetDescriptor ethereum = AssetDescriptor(
    id: ethereumId,
    symbol: 'ETH',
    providerSymbol: 'ETH-USD',
    name: 'Ethereum',
    category: AssetCategory.kripto,
    unit: AssetUnit.adet,
    currency: 'USD',
    description: 'Ethereum fiyatı (ETH/USD).',
  );

  // ---------------------------------------------------------------------------
  // KAYITLAR
  // ---------------------------------------------------------------------------

  static const List<AssetDescriptor> all = [
    // Borsa
    bist100,
    bist30,
    bist50,
    dxy,
    sp500,
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
    cadTry,
    audTry,
    cnyTry,
    // Emtia
    wtiCrude,
    brentCrude,
    platin,
    paladyum,
    bakir,
    dogalgaz,
    platinGram,
    // Kripto
    bitcoin,
    ethereum,
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
    wtiCrudeId,
    brentCrudeId,
    onsAltinId,
    onsGumusId,
  ];
}
