import '../../core/error/failures.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/news/news_impact.dart';
import '../../domain/providers/news_provider.dart';
import '../../domain/repositories/news_repository.dart';

/// RSS tabanli haber repository implementasyonu.
///
/// **Telif:** Yalnizca baslik, ozet, kaynak, zaman, kategori ve orijinal
/// baglanti tasinir. Tam haber metni istenmez ve depolanmaz.
class NewsRepositoryImpl implements NewsRepository {
  NewsRepositoryImpl(
    this._provider, {
    this.cacheTtl = const Duration(minutes: 5),
  });

  final NewsProvider _provider;
  final Duration cacheTtl;

  final Map<String, _Entry> _cache = {};

  Future<Result<List<NewsItem>>> _cached(
    String key,
    Future<Result<List<NewsItem>>> Function() fetch,
  ) async {
    final now = DateTime.now();
    final hit = _cache[key];
    if (hit != null && now.difference(hit.at) < cacheTtl) {
      return Success(hit.items);
    }
    final res = await fetch();
    if (res case Success(data: final items)) {
      _cache[key] = _Entry(items, now);
      return Success(items);
    }
    // Hata durumunda onbellekteki son gecerli veriyi dondur (cevrimdisi destegi).
    if (hit != null) return Success(hit.items);
    return res;
  }

  @override
  Future<Result<List<NewsItem>>> getNews({
    NewsCategory category = NewsCategory.sonDakika,
    int limit = 30,
  }) =>
      _cached('cat:${category.name}:$limit', () async {
        final all = await _provider.fetchAll(limit: 200);
        return all.when(
          onSuccess: (items) {
            if (category == NewsCategory.sonDakika) {
              final limited = items.take(limit).toList();
              if (limited.isEmpty) return const Err(EmptyFailure());
              return Success(limited);
            }
            final filtered =
                items.where((i) => i.category == category).take(limit).toList();
            if (filtered.isEmpty) {
              return Err(EmptyFailure(
                '${category.label} kategorisinde şu an haber yok.',
              ));
            }
            return Success(filtered);
          },
          onFailure: (f) => Err(f),
        );
      });

  @override
  Future<Result<List<NewsItem>>> getBreakingNews({int limit = 20}) =>
      getNews(category: NewsCategory.sonDakika, limit: limit);

  @override
  Future<Result<List<NewsItem>>> getNewsForAssets(
    List<String> assetIds, {
    int limit = 20,
  }) async {
    if (assetIds.isEmpty) {
      return const Err(EmptyFailure('Takip edilen varlık yok.'));
    }
    final all = await _provider.fetchAll(limit: 200);
    return all.when(
      onSuccess: (items) {
        // **Anahtar kelime taramasi yapilmaz.** Iliski [NewsImpact]
        // kurallariyla (haber kategorisi + spesifik varlik adi + merkez bankasi
        // olayi) belirlenir; boylece "dolar" kelimesi gecen her haber
        // USD'ye baglanmaz (onceki `contains` eslesmesi tam olarak bu
        // spam'i uretiyordu).
        final ids = assetIds.toSet();
        final out = <NewsItem>[];
        for (final item in items) {
          final links = NewsImpact.linksFor(item);
          if (links.isEmpty) continue;
          if (links.any((l) => ids.contains(l.assetId))) out.add(item);
        }
        out.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

        if (out.isEmpty) {
          return const Err(EmptyFailure(
            'Takip ettiğiniz varlıklarla ilgili güncel haber bulunamadı.',
          ));
        }
        return Success(out.take(limit).toList());
      },
      onFailure: (f) => Err(f),
    );
  }

  @override
  void invalidateCache() => _cache.clear();
}

class _Entry {
  _Entry(this.items, this.at);
  final List<NewsItem> items;
  final DateTime at;
}
