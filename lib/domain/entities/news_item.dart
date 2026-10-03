/// Haber kategorileri - tamamen Turkce.
enum NewsCategory {
  sonDakika('Son Dakika'),
  ekonomi('Ekonomi'),
  borsa('Borsa'),
  altin('Altın'),
  gumus('Gümüş'),
  doviz('Döviz'),
  sirketler('Şirketler'),
  merkezBankasi('Merkez Bankası'),
  dunyaEkonomisi('Dünya Ekonomisi');

  const NewsCategory(this.label);

  final String label;

  static NewsCategory? fromLabel(String label) {
    for (final c in NewsCategory.values) {
      if (c.label == label) return c;
    }
    return null;
  }
}

/// RSS beslemesinden tasinan haber kaydi.
///
/// Yalnizca baslik/ozet/kaynak/baglanti tasinir - tam metin degil.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.source,
    required this.publishedAt,
    required this.category,
    required this.url,
    this.summary,
    this.imageUrl,
  });

  /// Benzersiz anahtar (RSS guid veya hash).
  final String id;
  final String title;
  final String source;
  final DateTime publishedAt;
  final NewsCategory category;

  /// Orijinal habere giden baglanti.
  final String url;

  /// Kisa ozet (RSS description). Tam metin degil.
  final String? summary;
  final String? imageUrl;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  @override
  bool operator ==(Object other) => other is NewsItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NewsItem($id, $title)';
}
