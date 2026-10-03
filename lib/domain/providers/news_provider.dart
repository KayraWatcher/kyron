import '../../core/error/failures.dart';
import '../entities/news_item.dart';

/// Haber saglayici arayuzu.
///
/// Mimari: `UI -> State -> Repository -> NewsProvider -> RSS/API`
///
/// ## Telif notu
/// Bu arayuzden gecen veri **yalnizca** baslik, kisa ozet, kaynak, yayin
/// zamani, kategori, gorsel baglantisi ve orijinal habere giden baglantidir.
/// Haber metninin tamami asla istenmez, kopyalanmaz veya depolanmaz.
abstract interface class NewsProvider {
  /// Kaynak kimligi. Orn. `aa-rss`.
  String get id;

  /// Kaynagin okunabilir adi (kaynak etiketi olarak gosterilir).
  String get displayName;

  /// Beslemeden son haberleri getirir.
  ///
  /// Hata durumunda haber **uretilmez**; [Err] donulur.
  Future<Result<List<NewsItem>>> fetchAll({int limit = 30});
}
