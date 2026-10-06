import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/entities/quote.dart';
import '../../shared/shell/app_shell.dart';
import '../../shared/widgets/common.dart'
    show ScreenTitle, SectionHeader, StateSliver;
import '../../shared/widgets/price_flash.dart';
import '../../shared/widgets/quote_card.dart';
import '../../shared/widgets/watch_star.dart';
import '../alerts/alert_providers.dart';
import '../news/news_providers.dart';
import 'away_changes_card.dart';
import 'away_changes_provider.dart';
import 'dashboard_sections.dart';
import 'home_display.dart';
import 'home_display_sheet.dart';
import 'home_providers.dart';
import 'market_status_card.dart';
import 'market_status_provider.dart';
import 'mini_chart_providers.dart';
import 'touch_locked_order.dart';
import 'why_moving_card.dart';
import 'why_moving_providers.dart';

/// Ana Sayfa - 5 sekmenin ilk bolumu.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(homeQuotesProvider);
    final news = ref.watch(breakingNewsProvider);
    final display = ref.watch(homeDisplayProvider);
    final watch = ref.watch(watchlistProvider);

    // Istenen sira: filtre + siralama (saf fonksiyon, birim testli).
    // "Öne Çıkanlar" kullaniciya aittir: ekleme/cikarma/sira tercihi
    // [HomeDisplayState.pinned] icinden gelir ve kalicidir.
    final desired = applyHomeDisplay(
      featured: display.pinned,
      catalog: AssetCatalog.all,
      watchlist: watch,
      quotes: quotes.value ?? const <String, Quote>{},
      display: display,
    );

    // Dokunma kilidi: kullanici bir karta basili tutarken liste
    // yeniden siralanmaz; parmak kalkinca uygulanir.
    return TouchLockedOrder(
      desired: desired,
      builder: (ids) => RefreshIndicator(
        onRefresh: () => ref.read(homeQuotesProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ScreenTitle(
                      title: 'Ana Sayfa',
                      subtitle: _subtitle(quotes),
                    ),
                  ),
                  _displayButton(context, ref),
                  _viewButton(ref, display),
                  _themeButton(context, ref),
                  _alertsButton(context, ref),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Piyasalar',
                action: display.filter == HomeFilter.onecikanlar
                    ? 'Tümü'
                    : display.filter.label,
                onAction: () {
                  if (display.filter == HomeFilter.onecikanlar) {
                    selectSection(ref, AppSection.markets);
                  } else {
                    showHomeDisplaySheet(context, ref);
                  }
                },
              ),
            ),

            // ---- Sen Yokken Ne Oldu? ----
            SliverToBoxAdapter(child: const AwayChangesCard()),

            // ---- Quote grid dogrudan sliver olarak (StateSliver) eklenir;
            // SliverToBoxAdapter icine alinamaz (tip protokolu hatasi).
            _quoteGrid(context, ref, quotes, ids, display),

            // ---- Günün en çok hareket edenleri ----
            const SliverToBoxAdapter(child: TopMoversSection()),

            // ---- Kategoriler ----
            const SliverToBoxAdapter(child: CategoryNavSection()),

            // ---- Takip Listesi (bossa gizlenir: ana sayfa kalabalik olmasin)
            if (watch.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Takip Edilenler',
                  action: 'Piyasalar',
                  onAction: () => selectSection(ref, AppSection.markets),
                ),
              ),
              _watchlist(context, ref, quotes),
            ],

            // ---- Neden Hareket Ediyor? (Öne Çıkanlar için) ----
            SliverToBoxAdapter(
              child: _WhyMovingSection(ids: ids, quotes: quotes),
            ),

            // ---- Son Dakika ----
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Son Dakika Haberleri',
                action: 'Tümü',
                onAction: () => selectSection(ref, AppSection.news),
              ),
            ),
            _newsSliver(context, ref, news),

            // ---- Imza (uygulamanin en alti) ----
            const SliverToBoxAdapter(child: _AppFooter()),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  /// Filtre + siralama ac butonu. Varsayilan disinda bir secim varsa
  /// ustunde bir nokta gosterir (aktif filtre gorunur).
  Widget _displayButton(BuildContext context, WidgetRef ref) {
    final display = ref.watch(homeDisplayProvider);
    final active = !display.isDefault;

    return IconButton(
      tooltip: active
          ? 'Filtre ve sıralama (${display.filter.label} · ${display.sort.label})'
          : 'Filtre ve sıralama',
      padding: EdgeInsets.zero,
      onPressed: () => showHomeDisplaySheet(context, ref),
      icon: Badge(
        isLabelVisible: active,
        smallSize: 7,
        backgroundColor: AppPalette.gold,
        child: const Icon(Icons.tune_rounded),
      ),
    );
  }

  /// Gorunum secici: Izgara / Liste.
  Widget _viewButton(WidgetRef ref, HomeDisplayState display) {
    final isGrid = display.view == HomeViewMode.grid;
    return IconButton(
      tooltip: isGrid ? 'Liste görünüme geç' : 'Izgara görünüme geç',
      padding: EdgeInsets.zero,
      onPressed: () => ref
          .read(homeDisplayProvider.notifier)
          .setView(isGrid ? HomeViewMode.list : HomeViewMode.grid),
      icon: Icon(isGrid ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
    );
  }

  /// Tema secici (Acik / Koyu / Sistem).
  /// Sistem varsayilani uygulama ici elle secilebilir hale getirir.
  Widget _themeButton(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
    final label = switch (mode) {
      ThemeMode.light => 'Açık tema',
      ThemeMode.dark => 'Koyu tema',
      ThemeMode.system => 'Sistem teması',
    };

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema ($label)',
      padding: EdgeInsets.zero,
      icon: Icon(icon),
      onSelected: (m) => ref.read(themeModeProvider.notifier).set(m),
      itemBuilder: (context) => const [
        PopupMenuItem(value: ThemeMode.system, child: Text('Sistem')),
        PopupMenuItem(value: ThemeMode.light, child: Text('Açık')),
        PopupMenuItem(value: ThemeMode.dark, child: Text('Koyu')),
      ],
    );
  }

  /// Alarmlar giris butonu - acik alarm sayisini rozet olarak gosterir.
  /// Ayrica alarm izleyicisinin (watchdog) ayakta kalmasini saglar.
  Widget _alertsButton(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final active = alerts.where((a) => a.enabled).length;

    return IconButton(
      tooltip: 'Alarmlar',
      onPressed: () => openAlerts(context),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }

  String _subtitle(AsyncValue<Map<String, Quote>> quotes) {
    final now = DateTime.now();
    final date = TrFormat.date(now);
    return date;
  }

  Widget _quoteGrid(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, Quote>> quotes,
    List<String> desiredIds,
    HomeDisplayState display,
  ) {
    final view = toViewState<Map<String, Quote>>(
      quotes,
      isEmpty: (m) => m.isEmpty,
    );

    return StateSliver<Map<String, Quote>>(
      state: view,
      onRetry: () => ref.read(homeQuotesProvider.notifier).refresh(),
      emptyMessage: 'Fiyat verisi alınamadı.',
      sliverBuilder: (map) {
        // Sira dokunma kilidinden gelir; verisi gelmeyenler elenir.
        final ids = desiredIds.where(map.containsKey).toList();

        // Filtre secili ama o kategoride gosterilecek varlik yok
        // (orn. "Fonlar" - katalogda fund kaydi yok). Uydurma veri uretilmez.
        if (ids.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: EmptyStateView(
                message: 'Bu filtrede gösterilecek varlık yok.',
                icon: Icons.filter_alt_off_rounded,
              ),
            ),
          );
        }

        // Liste gorunumu: Takip Edilenler ile **AYNI** asset-row deseni
        // (ortak satir sliver'i - kopya component olusturulmaz).
        if (display.view == HomeViewMode.list) {
          return _assetRowSliver(ids, map);
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 176,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final id = ids[i];
                return Consumer(
                  builder: (context, ref, _) {
                    final spark = ref.watch(
                      miniChartProvider(id),
                    );
                    return QuoteCard(
                      assetId: id,
                      quote: map[id]!,
                      sparkline: spark.value,
                      showSpread: false,
                      trailing: WatchStar(assetId: id, size: 20),
                      onTap: () => openAssetDetail(context, id),
                    );
                  },
                );
              },
              childCount: ids.length,
            ),
          ),
        );
      },
    );
  }

  /// "Piyasalar" (liste görünümlü) ve "Takip Edilenler" için **ortak** asset
  /// satırı sliver'ı.
  ///
  /// İki bölüm aynı [WatchRow] desenini (kimlik · sparkline · fiyat/değişim),
  /// aynı ayırıcı aralığı ve aynı kenar boşluğunu kullanır; böylece yan yana
  /// karşılaştırıldığında aynı varlık-satır sisteminin parçaları gibi görünür.
  /// Yeni bir satır component'i kopyalanmaz.
  SliverList _assetRowSliver(List<String> ids, Map<String, Quote> quotes) {
    return SliverList.separated(
      itemCount: ids.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final id = ids[i];
        return WatchRow(assetId: id, quote: quotes[id]!);
      },
    );
  }

  Widget _watchlist(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, Quote>> quotes,
  ) {
    final watch = ref.watch(watchlistProvider);
    final view = toViewState<Map<String, Quote>>(
      quotes,
      isEmpty: (m) => m.isEmpty,
    );

    return StateSliver<Map<String, Quote>>(
      state: view,
      onRetry: () => ref.read(homeQuotesProvider.notifier).refresh(),
      emptyMessage: 'Takip listesi boş.',
      sliverBuilder: (map) {
        final ids = watch.where((id) => map.containsKey(id)).toList();
        if (ids.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EmptyStateView(
                message: 'Takip edilen varlık bulunamadı.',
                icon: Icons.star_border_rounded,
              ),
            ),
          );
        }
        return _assetRowSliver(ids, map);
      },
    );
  }

  Widget _newsSliver(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<NewsItem>> news,
  ) {
    final view = toViewState<List<NewsItem>>(
      news,
      isEmpty: (list) => list.isEmpty,
    );

    return StateSliver<List<NewsItem>>(
      state: view,
      onRetry: () => ref.read(breakingNewsProvider.notifier).refresh(),
      emptyMessage: 'Şu an gösterilecek haber yok.',
      emptyIcon: Icons.newspaper_rounded,
      sliverBuilder: (items) {
        final top = items.take(6).toList();
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _NewsTile(item: top[i]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// "Neden Hareket Ediyor?" bölümü (Öne Çıkan varlıklar için)
// ---------------------------------------------------------------------------

class _WhyMovingSection extends ConsumerWidget {
  const _WhyMovingSection({
    required this.ids,
    required this.quotes,
  });

  final List<String> ids;
  final AsyncValue<Map<String, Quote>> quotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = quotes.value;
    if (map == null || map.isEmpty) return const SizedBox.shrink();

    // Sadece % degisimi belirgin olanlari analiz et (> 0.5%)
    final significant = ids.where((id) {
      final q = map[id];
      return q != null &&
          q.effectiveChangePercent != null &&
          q.effectiveChangePercent!.abs() > 0.5;
    }).toList();

    if (significant.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Neden Hareket Ediyor?',
          action: '',
          onAction: null,
        ),
        const SizedBox(height: 4),
        ...significant.take(3).map((id) => WhyMovingCard(assetId: id)),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Imza
// ---------------------------------------------------------------------------

/// Uygulamanin en altinda duran gelistirici imzasi.
class _AppFooter extends StatelessWidget {
  const _AppFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            'KYRON · Türkiye Piyasa takibi',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppPalette.neutral),
          ),
          const SizedBox(height: 4),
          Text(
            'Kayra ÇIKLA',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppPalette.goldDeep,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak asset satiri (Piyasalar-liste + Takip Edilenler)
// ---------------------------------------------------------------------------

/// Anasayfanin **ortak asset satiri**.
///
/// Hem "Piyasalar" (liste gorunumu) hem "Takip Edilenler" bu satiri kullanir:
/// [AssetIdentity] (sol) · [Sparkline] (orta) · fiyat + [ChangeBadge] (sağ).
/// Ayni satir tek yerden gelir; baska bir kopya satir component'i
/// olusturulmaz. Satir icinde Alis/Satis gosterilmez.
class WatchRow extends ConsumerWidget {
  const WatchRow({super.key, required this.assetId, required this.quote});

  final String assetId;
  final Quote quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final changePercent = quote.effectiveChangePercent;
    final color = AppPalette.direction(changePercent);
    final spark = ref.watch(miniChartProvider(assetId));

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => openAssetDetail(context, assetId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: AssetIdentity(
                  assetId: assetId,
                  subtitle: quote.source.label,
                  freshness: quote.freshness,
                  isStale: quote.isStale,
                ),
              ),
              Sparkline(data: spark.value, color: color, width: 56),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PriceFlash(
                      text: quote.price == null
                          ? TrFormat.noData
                          : TrFormat.price(quote.price),
                      price: quote.price,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    ChangeBadge(
                      value: changePercent,
                      percent: true,
                      compact: true,
                      showArrow: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Haber satiri
// ---------------------------------------------------------------------------

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item});

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kompakt thumbnail: gerçek görsel varsa o, yoksa fallback.
              _NewsThumb(url: item.imageUrl ?? ''),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _sourceBadge(context, item.category.label),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppPalette.goldDeep,
        ),
      ),
    );
  }
}

/// Ana sayfa haber onizleme gorseli (News ekranindaki ile ayni mantik).
///
/// Gercek gorsel varsa onu gosterir; yoksa/alinamazsa candlestick
/// finans ikonu yer tutucusu gosterilir. Sahte gorsel uretilmez.
class _NewsThumb extends StatelessWidget {
  const _NewsThumb({required this.url});

  final String url;

  static const double _w = 56;
  static const double _h = 44;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final usable =
        uri != null && (uri.isScheme('http') || uri.isScheme('https'));

    final placeholder = Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        // Kart zemininden net ayrilan gorunur yer tutucu:
        // altin tonlu finans kutusu + candlestick ikonu (sahte gorsel degil).
        color: AppPalette.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.goldDeep.withValues(alpha: 0.55)),
      ),
      child: const Icon(
        Icons.candlestick_chart_rounded,
        size: 22,
        color: AppPalette.gold,
      ),
    );

    if (!usable) return placeholder;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: _w,
          height: _h,
          fit: BoxFit.cover,
          cacheWidth: (_w * 3).round(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : placeholder,
          errorBuilder: (context, error, stack) => placeholder,
        ),
      ),
    );
  }
}










