/// Varlik kategorileri - Piyasalar bolumunun ayristirma anahtari.
enum AssetCategory {
  borsa('Borsa'),
  altin('Altın'),
  gumus('Gümüş'),
  doviz('Döviz'),
  kripto('Kripto'),
  emtia('Emtia');

  const AssetCategory(this.label);

  final String label;
}

/// Varlik birimi - portfoy hesaplarinda miktarin ne ifade ettigi.
enum AssetUnit {
  adet('adet'),
  gram('gram'),
  ons('ons'),
  para('para'),
  puan('puan'),
  varil('varil'),
  /// Emtia birimleri: bakır USD/libre, doğalgaz USD/MMBtu.
  libre('libre'),
  mmbtu('MMBtu');

  const AssetUnit(this.label);

  final String label;
}

/// Uygulama genelinde kullanilan sabit varlik tanimi.
///
/// Semboller tek noktada tanimlanir; boylece ayni varlik Piyasalar,
/// Ana Sayfa, Portfoy ve Alarm ekranlarinda tutarli gosterilir.
class AssetDescriptor {
  const AssetDescriptor({
    required this.id,
    required this.symbol,
    required this.name,
    required this.category,
    required this.unit,
    required this.currency,
    this.providerSymbol,
    this.chartProviderSymbol,
    this.isCalculated = false,
    this.parentIds = const [],
    this.description,
  });

  /// Icerik ici benzersiz anahtar. Orn. "gram-altin".
  final String id;

  /// Kaynak sembol. Yahoo icin "THYAO.IS", TCMB icin "USD".
  final String symbol;

  /// Turkce gosterim adi. Orn. "Gram Altın".
  final String name;

  final AssetCategory category;
  final AssetUnit unit;

  /// Fiyat birimi. "TRY" | "USD" ...
  final String currency;

  /// Provider'a gonderilecek sembol; [symbol]dan farkliysa.
  ///
  /// **Fiyat (current price)** istekleri icin kullanilir. SPOT veri veren
  /// saglayicilar (Gold API `XAU`/`XAG`) ile sembol burada tanimlanir.
  final String? providerSymbol;

  /// Grafik (mum/OHLC) serisi icin farkli sembol gereken varliklarda
  /// kullanilan sembol; null ise [fetchSymbol] kullanilir.
  ///
  /// **Neden ayrildi:** Ons Altin/Ons Gümüş'ün **fiyati** Gold API'den
  /// SPOT `XAU`/`XAG` olarak gelirken, Yahoo `XAU`/`XAG` chart ucunda
  /// kalici olarak **HTTP 404** dondurur. Ayni sembolu kullanmak grafiklerin
  /// (ve onlardan hesaplanan gram altin/gram gumus grafiginin) kirilmasina
  /// yol aciyordu. Buradaki sembol yalnizca **grafik** icindir; fiyat
  /// saglayicisini veya spot fiyat etiketini degistirmez.
  final String? chartProviderSymbol;

  /// Dogrudan kaynak verisi degil, bilesenlerden hesaplaniyor mu.
  final bool isCalculated;

  /// Hesaplanan varlik icin hangi varliklarin kullanildigi.
  final List<String> parentIds;

  final String? description;

  /// Kullanimi kolay fetch sembolu.
  String get fetchSymbol => providerSymbol ?? symbol;

  /// Grafik/mum (OHLC) istekleri icin fetch sembolu.
  ///
  /// Varsayilan olarak [fetchSymbol] ile aynidir; sembol ayri gerekmedikce
  /// hicbir varlik icin davranis degismez.
  String get fetchChartSymbol => chartProviderSymbol ?? fetchSymbol;

  @override
  bool operator ==(Object other) => other is AssetDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AssetDescriptor($id)';
}
