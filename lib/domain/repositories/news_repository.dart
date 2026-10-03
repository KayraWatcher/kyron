import '../../core/error/failures.dart';
import '../entities/news_item.dart';

/// Haber repository arayuzu.
///
/// **Telif notu:** Yalnizca baslik, ozet, kaynak, zaman ve orijinal baglanti
/// tasinir. Haber metninin tamami asla kopyalanmaz/depolanmaz.
abstract interface class NewsRepository {
  /// Kategoriye gore haber akisi.
  Future<Result<List<NewsItem>>> getNews({
    NewsCategory category = NewsCategory.sonDakika,
    int limit = 30,
  });

  /// Tum kategorilerden son dakika akisi.
  Future<Result<List<NewsItem>>> getBreakingNews({int limit = 20});

  /// Takip edilen varliklarla iliskili haberler.
  Future<Result<List<NewsItem>>> getNewsForAssets(
    List<String> assetIds, {
    int limit = 20,
  });

  /// Onbellekteki tum haberleri dusurur.
  ///
  /// **Ne zaman cagrilir:** yalnizca kullanici acikca yenileme istediginde
  /// (cek-yenile / "Yenile" dugmesi / hata sonrasi tekrar deneme). Otomatik
  /// yuklemeler TTL'ye uyar; kullanici yenilemesi beklemez.
  void invalidateCache();
}
