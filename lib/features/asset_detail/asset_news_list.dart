import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/news/news_impact.dart';

/// Varlık detay ekranındaki **ilgili haberler** listesi.
///
/// **İlişki kuralı:** [NewsImpact] ile belirlenir — haber kategorisi, spesifik
/// varlık adı veya merkez bankası olayı. Anahtar kelime taraması yapılmaz
/// ("dolar" kelimesi geçen her haber USD'ye bağlanmaz).
///
/// Hesaplanan varlıklarda (gram altın gibi) **bileşenlerinin** haberleri de
/// gösterilir; çünkü fiyat o bileşenlerden gelir ve haber onları etkiler.
///
/// Kanıt yoksa bölüm **hiç gösterilmez** (boş kutu / "haber yok" yazısı
/// yerine sessiz kalır); yalnızca yükleniyor/hata durumunda küçük bir durum
/// metni gösterilir.
class AssetNewsList extends ConsumerWidget {
  const AssetNewsList({
    super.key,
    required this.assetId,
    this.parentIds = const <String>[],
  });

  final String assetId;
  final List<String> parentIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assetNewsProvider((assetId, parentIds)));

    return async.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu varlıkla ilişkisi doğrulanabilen güncel haber yok.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.neutral, fontSize: 13),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _NewsRow(item: items[i]),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Haberler yükleniyor…',
            style: TextStyle(color: AppPalette.neutral, fontSize: 13),
          ),
        ),
      ),
      error: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Haberler alınamadı.',
            style: TextStyle(color: AppPalette.neutral, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// Varlığa (veya bileşenlerine) ilişkili güncel haberler.
final assetNewsProvider = FutureProvider.autoDispose
    .family<List<NewsItem>, (String, List<String>)>((ref, key) async {
  final (assetId, parentIds) = key;
  final repo = ref.watch(newsRepositoryProvider);
  final res = await repo.getNews(limit: 120);
  return res.when(
    onSuccess: (items) {
      final targets = <String>{assetId, ...parentIds};
      final out = <NewsItem>[];
      for (final item in items) {
        final links = NewsImpact.linksFor(item);
        if (links.isEmpty) continue;
        if (links.any((l) => targets.contains(l.assetId))) out.add(item);
      }
      out.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return out.take(20).toList();
    },
    onFailure: (f) => <NewsItem>[],
  );
});

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => launchNewsUrl(item.url),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppPalette.gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category.label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.goldDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    TrFormat.relativeTime(item.publishedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.neutral,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
