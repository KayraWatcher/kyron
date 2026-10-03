import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/state_failure.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/news_item.dart';
import '../home/home_providers.dart';

/// Haber kategorisi secimi.
final newsCategoryProvider =
    NotifierProvider<NewsCategoryNotifier, NewsCategory>(
  NewsCategoryNotifier.new,
);

class NewsCategoryNotifier extends Notifier<NewsCategory> {
  @override
  NewsCategory build() => NewsCategory.sonDakika;

  void select(NewsCategory category) => state = category;
}

/// Son dakika haberi akisi (Ana Sayfa ve Haberler bolumu paylasir).
final breakingNewsProvider =
    AsyncNotifierProvider<BreakingNewsNotifier, List<NewsItem>>(
  BreakingNewsNotifier.new,
);

class BreakingNewsNotifier extends AsyncNotifier<List<NewsItem>> {
  @override
  Future<List<NewsItem>> build() => _load();

  Future<List<NewsItem>> _load() async {
    final repo = ref.watch(newsRepositoryProvider);
    final res = await repo.getBreakingNews(limit: 20);
    return res.when(
      onSuccess: (items) => items,
      onFailure: (f) => throw StateFailure(f),
    );
  }

  Future<void> refresh() async {
    // Kullanici acikca yenileme istedi: 5 dakikalik onbellek TTL'ini
    // beklemeden taze kaynak cekilir. (Eski hata: `ref.read(...)` hicbir
    // sey yapmiyordu - cek-yenile ayni eski veriyi gosteriyordu.)
    ref.read(newsRepositoryProvider).invalidateCache();
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

/// Secili kategorideki haberler.
final categoryNewsProvider = FutureProvider.autoDispose
    .family<List<NewsItem>, NewsCategory>((ref, category) async {
  final repo = ref.watch(newsRepositoryProvider);
  final res = await repo.getNews(category: category, limit: 40);
  return res.when(
    onSuccess: (items) => items,
    onFailure: (f) => throw StateFailure(f),
  );
});

/// Takip edilen varliklarla ilgili haberler.
final watchlistNewsProvider =
    FutureProvider.autoDispose<List<NewsItem>>((ref) async {
  final watch = ref.watch(watchlistProvider);
  final repo = ref.watch(newsRepositoryProvider);
  final res = await repo.getNewsForAssets(watch, limit: 20);
  return res.when(
    onSuccess: (items) => items,
    onFailure: (f) => throw StateFailure(f),
  );
});
