import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/news_item.dart';
import '../../shared/widgets/common.dart';
import 'news_providers.dart';

/// Haberler - Turkce haber merkezi (Aşama 12).
///
/// **Telif:** Her haber yalnizca baslik + ozet + kaynak + zaman +
/// orijinal baglanti olarak gosterilir. Tam metin asla gosterilmez.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  static const List<NewsCategory> _tabs = [
    NewsCategory.sonDakika,
    NewsCategory.ekonomi,
    NewsCategory.borsa,
    NewsCategory.altin,
    NewsCategory.gumus,
    NewsCategory.doviz,
    NewsCategory.sirketler,
    NewsCategory.merkezBankasi,
    NewsCategory.dunyaEkonomisi,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(newsCategoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenTitle(
          title: 'Haberler',
          subtitle: 'Ekonomi ve piyasa haberleri — kaynak özetleri',
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _tabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _tabs[i];
              final selected = c == category;
              return ChoiceChip(
                label: Text(c.label),
                selected: selected,
                onSelected: (_) =>
                    ref.read(newsCategoryProvider.notifier).select(c),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(child: _NewsBody(category: category)),
      ],
    );
  }
}

class _NewsBody extends ConsumerWidget {
  const _NewsBody({required this.category});

  final NewsCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category == NewsCategory.sonDakika) {
      final async = ref.watch(breakingNewsProvider);
      final view = toViewState<List<NewsItem>>(
        async,
        isEmpty: (l) => l.isEmpty,
      );
      return StateView<List<NewsItem>>(
        state: view,
        onRetry: () => ref.read(breakingNewsProvider.notifier).refresh(),
        emptyMessage: 'Şu an gösterilecek haber yok.',
        emptyIcon: Icons.newspaper_rounded,
        builder: (items) => _NewsList(items: items, category: category),
      );
    }

    final async = ref.watch(categoryNewsProvider(category));
    final view = toViewState<List<NewsItem>>(async, isEmpty: (l) => l.isEmpty);
    return StateView<List<NewsItem>>(
      state: view,
      onRetry: () => ref.invalidate(categoryNewsProvider(category)),
      emptyMessage: '${category.label} kategorisinde şu an haber yok.',
      emptyIcon: Icons.newspaper_rounded,
      builder: (items) => _NewsList(items: items, category: category),
    );
  }
}

class _NewsList extends ConsumerWidget {
  const _NewsList({required this.items, required this.category});

  final List<NewsItem> items;
  final NewsCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyStateView(
        message: 'Gösterilecek haber bulunamadı.',
        icon: Icons.newspaper_rounded,
      );
    }

    Future<void> refresh() async {
      if (category == NewsCategory.sonDakika) {
        await ref.read(breakingNewsProvider.notifier).refresh();
      } else {
        // Cek-yenile onbellek TTL'ini beklemez (yoksa kullanici ayni
        // eski listeyi ceker gibi yapar).
        ref.read(newsRepositoryProvider).invalidateCache();
        ref.invalidate(categoryNewsProvider(category));
        await ref.read(categoryNewsProvider(category).future);
      }
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _NewsCard(item: items[i]),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Yalnizca haberin kategorisinden dogrulanabilen iliskiler gosterilir;
    // basliga gore anahtar kelime taramasiyla tahmin uretilmez.
    final affectedMarkets = _affectedMarketsFor(item.category);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => launchNewsUrl(item.url),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category.label,
                      style: const TextStyle(
                        fontSize: 10.5,
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
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.imageUrl != null) ...[
                    _NewsThumb(url: item.imageUrl!),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        if (item.summary != null &&
                            item.summary!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.summary!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ---- Etkilenen Piyasalar ----
              if (affectedMarkets.isNotEmpty) ...[
                _AffectedMarketsRow(markets: affectedMarkets),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Orijinal habere git',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Haber kategorisine gore etkilenen piyasalar.
///
/// **Dogrulama politikasi:** Iliski yalnizca haberin editoryal kategorisinden
/// uretilir; baslik/ozet uzerinden anahtar kelime taramasi yapilmaz.
/// Kategori varligi dogrulanamayan piyasalar (Son Dakika, Ekonomi,
/// Sirketler, Merkez Bankasi, Dunya Ekonomisi) hic gosterilmez.
List<String> _affectedMarketsFor(NewsCategory category) {
  switch (category) {
    case NewsCategory.altin:
      return const ['Ons Altın', 'Gram Altın'];
    case NewsCategory.gumus:
      return const ['Ons Gümüş', 'Gram Gümüş'];
    case NewsCategory.doviz:
      return const ['USD/TRY', 'EUR/TRY'];
    case NewsCategory.borsa:
      return const ['BIST 100'];
    case NewsCategory.sonDakika:
    case NewsCategory.ekonomi:
    case NewsCategory.sirketler:
    case NewsCategory.merkezBankasi:
    case NewsCategory.dunyaEkonomisi:
      return const [];
  }
}

/// "Etkilenen piyasalar" etiket satiri (salt bilgi, etkilesimsiz).
class _AffectedMarketsRow extends StatelessWidget {
  const _AffectedMarketsRow({required this.markets});

  final List<String> markets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.link_rounded,
              size: 14,
              color: AppPalette.goldDeep,
            ),
            const SizedBox(width: 6),
            Text(
              'Etkilenen piyasalar',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppPalette.goldDeep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: markets
              .map((m) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppPalette.gold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      m,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.goldDeep,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

/// Haber onizleme gorseli.
///
/// **Bellek/performans (Aşama 16):**
///  * `cacheWidth` ile decode boyutu 3 kat kirpilir; 4000px'lik haber
///    fotografi bellekte ~16 MB degil ~0.4 MB yer kaplar.
///  * `RepaintBoundary` ile liste kaydirmasinda yalitilir.
///
/// **Dürüstlük:** Gorsel yoksa/alinamazsa ikon yer tutucusu gosterilir -
/// hicbir zaman yanlis bir gorsel veya bos kutu sunulmaz.
class _NewsThumb extends StatelessWidget {
  const _NewsThumb({required this.url});

  final String url;

  static const double _w = 84;
  static const double _h = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(url);
    final usable =
        uri != null && (uri.isScheme('http') || uri.isScheme('https'));

    final placeholder = Container(
      width: _w,
      height: _h,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.newspaper_rounded,
        size: 22,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (!usable) return placeholder;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: _w,
          height: _h,
          fit: BoxFit.cover,
          // 84pt * 3 (en yuksek standart olcek) - decode maliyetini kisar.
          cacheWidth: (_w * 3).round(),
          // Yuklenirken yer tutucu; hata durumunda ikon gosterilir.
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return placeholder;
          },
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}
