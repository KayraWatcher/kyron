/// Varlik kategorileri - Piyasalar bolumunun ayristirma anahtari.
enum AssetCategory {
  borsa('Borsa'),
  altin('Altın'),
  gumus('Gümüş'),
  doviz('Döviz'),
  fon('Fonlar');

  const AssetCategory(this.label);

  final String label;
}

/// Varlik birimi - portfoy hesaplarinda miktarin ne ifade ettigi.
enum AssetUnit {
  adet('adet'),
  gram('gram'),
  ons('ons'),
  para('para'),
  puan('puan');

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
  final String? providerSymbol;

  /// Dogrudan kaynak verisi degil, bilesenlerden hesaplaniyor mu.
  final bool isCalculated;

  /// Hesaplanan varlik icin hangi varliklarin kullanildigi.
  final List<String> parentIds;

  final String? description;

  /// Kullanimi kolay fetch sembolu.
  String get fetchSymbol => providerSymbol ?? symbol;

  @override
  bool operator ==(Object other) => other is AssetDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AssetDescriptor($id)';
}
