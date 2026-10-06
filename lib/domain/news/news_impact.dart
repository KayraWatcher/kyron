import '../entities/asset_catalog.dart';
import '../entities/news_item.dart';

/// Haber -> varlik iliskisinin **kanit gucu**.
///
/// Guclu kanit: haberin editoryal kategorisi dogrudan o piyasayi isaret eder.
/// Orta kanit: baslik/ozette **spesifik** bir varlik adi ya da bir olay
/// kalibi (merkez bankasi karari, faiz/enflasyon aciklamasi) geciyor.
///
/// **Tasarim kurali (spam yasagi):** "dolar", "kur", "borsa" gibi **cift
/// anlamli tek kelimeler** baslikta gecse bile iliski kurulmaz. Aksi halde
/// "dolar" kelimesi gecen her haber USD'ye baglanir ve bolum anlamini
/// yitirir. Iliski ancak yukaridaki iki kanit sinifindan biri saglanirsa
/// kurulur; kurulmazsa **hicbir sey gosterilmez**.
enum ImpactStrength {
  /// Haberin editoryal kategorisi dogrudan bu piyasayi isaret eder.
  kategori,

  /// Baslik/ozette spesifik varlik adi veya olay kalibi geciyor.
  sinyal,
}

/// Bir haberin bir varlikla iliskisi.
class NewsImpactLink {
  const NewsImpactLink({
    required this.assetId,
    required this.strength,
    required this.reason,
  });

  final String assetId;
  final ImpactStrength strength;

  /// Kullaniciya gosterilen kisa gerekce (neye dayaniyor).
  final String reason;

  /// Varlik adi (katalogda yoksa null).
  String? get assetName => AssetCatalog.byId(assetId)?.name;
}

/// Haber ile varlik arasindaki **korumali** iliski motoru.
///
/// Hem "Neyi etkileyebilir?" (haber -> varlik) hem de varlik detayindaki
/// "ilgili haberler" (varlik -> haber) yonu ayni kurallari kullanir; boylece
/// iki yon birbiriyle celismeyen ayni mantigi paylasir.
abstract final class NewsImpact {
  /// Haber kategorisi -> dogrudan ilgili varliklar (kanit: kategori).
  static const Map<NewsCategory, List<String>> _byCategory = {
    NewsCategory.altin: [AssetCatalog.onsAltinId, AssetCatalog.gramAltinId],
    NewsCategory.gumus: [AssetCatalog.onsGumusId, AssetCatalog.gramGumusId],
    NewsCategory.doviz: [AssetCatalog.usdTryId, AssetCatalog.eurTryId],
    NewsCategory.borsa: [AssetCatalog.bist100Id],
  };

  /// Baslik/ozette aranan **spesifik** varlik anahtarlari.
  ///
  /// Anahtarlar bilerek uzun/ozgul secilmistir; tek anlamli kisa kelimeler
  /// (orn. "dolar") burada **yer almaz**.
  static const List<(String, String, String)> _entitySignals = [
    // (anahtar kelime, assetId, gerekce)
    ('brent', AssetCatalog.brentCrudeId, 'Brent petrol haberi'),
    ('ham petrol', AssetCatalog.wtiCrudeId, 'Ham petrol haberi'),
    ('petrol', AssetCatalog.wtiCrudeId, 'Petrol haberi'),
    ('paladyum', AssetCatalog.paladyumId, 'Paladyum haberi'),
    ('platin', AssetCatalog.platinId, 'Platin haberi'),
    ('doğalgaz', AssetCatalog.dogalgazId, 'Doğalgaz haberi'),
    ('dogalgaz', AssetCatalog.dogalgazId, 'Doğalgaz haberi'),
    ('bakır', AssetCatalog.bakirId, 'Bakır haberi'),
    ('bakir', AssetCatalog.bakirId, 'Bakır haberi'),
    ('bitcoin', AssetCatalog.bitcoinId, 'Bitcoin haberi'),
    ('btc', AssetCatalog.bitcoinId, 'Bitcoin haberi'),
    ('ethereum', AssetCatalog.ethereumId, 'Ethereum haberi'),
    ('bist 100', AssetCatalog.bist100Id, 'BIST 100 haberi'),
  ];

  /// Merkez bankasi / ekonmik politika **olay** kaliplari.
  ///
  /// Yalnizca acik bir **olay** ifadesi sayilir ("fed faiz kararı" gibi).
  /// Merkez bankasi adinin gecmesi tek basina yeterlidir; buna karsilik
  /// cift anlamli "dolar"/"kur" kelimeleri yeterli degildir.
  static const List<(List<String>, String)> _macroEvents = [
    (
      ['fed', 'federal reserve', 'powell'],
      'Merkez bankası haberi (ABD)',
    ),
    (
      ['tcmb', 'merkez bankası', 'merkez bankasi', 'karahan'],
      'Merkez bankası haberi',
    ),
    (['ecb', 'avrupa merkez bankası'], 'Merkez bankası haberi (ABD)'),
  ];

  /// Merkez bankasi haberinin **birebir** ilgili olduğu varliklar.
  static const List<String> _macroAssets = [
    AssetCatalog.usdTryId,
    AssetCatalog.onsAltinId,
    AssetCatalog.bist100Id,
  ];

  /// Haberin metni (baslik + ozet) - kucuk harfe indirgenmis.
  static String _haystack(NewsItem item) {
    final parts = <String>[item.title];
    final summary = item.summary;
    if (summary != null && summary.isNotEmpty) parts.add(summary);
    return parts.join(' ').toLowerCase();
  }

  /// Bir haberin iliskili oldugu varliklar (gerekce + kanit gucu ile).
  static List<NewsImpactLink> linksFor(NewsItem item) {
    final out = <String, NewsImpactLink>{};

    // 1) Kanit: editoryal kategori.
    for (final id in _byCategory[item.category] ?? const <String>[]) {
      out[id] = NewsImpactLink(
        assetId: id,
        strength: ImpactStrength.kategori,
        reason: '${item.category.label} haberi',
      );
    }

    final text = _haystack(item);

    // 2) Kanit: spesifik varlik adi.
    for (final (keyword, assetId, reason) in _entitySignals) {
      if (out.containsKey(assetId)) continue;
      if (text.contains(keyword)) {
        out[assetId] = NewsImpactLink(
          assetId: assetId,
          strength: ImpactStrength.sinyal,
          reason: reason,
        );
      }
    }

    // 3) Kanit: merkez bankasi / ekonmik politika olayi.
    for (final (needles, reason) in _macroEvents) {
      final hit = needles.any(text.contains);
      if (!hit) continue;
      for (final id in _macroAssets) {
        if (out.containsKey(id)) continue;
        out[id] = NewsImpactLink(
          assetId: id,
          strength: ImpactStrength.sinyal,
          reason: reason,
        );
      }
    }

    return out.values.toList(growable: false);
  }

  /// Haberin iliskili oldugu varlik id'leri (bos olabilir).
  static List<String> assetIdsFor(NewsItem item) =>
      linksFor(item).map((l) => l.assetId).toList(growable: false);

  /// Verilen haber havuzunda bir varlikla **gercekten** iliskili haberler.
  ///
  /// Anahtar kelime taramasi YAPILMAZ; ayni [linksFor] kurallari kullanilir.
  static List<NewsItem> newsForAsset(List<NewsItem> items, String assetId) {
    final out = <NewsItem>[];
    for (final item in items) {
      if (linksFor(item).any((l) => l.assetId == assetId)) out.add(item);
    }
    out.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return out;
  }

  /// Bir varlik icin habere donus **etiketler** (varlik detay ekrani).
  ///
  /// Yalnizca kanit varsa doner; kanit yoksa **bos liste** doner (UI'da
  /// bolum hic gosterilmez).
  static List<String> labelsFor(NewsItem item) =>
      linksFor(item).map((l) => l.reason).toList(growable: false);
}
