import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/navigator_utils.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/quote_card.dart';
import '../../shared/widgets/watch_star.dart';
import 'markets_providers.dart';

/// Piyasalar - kategori bazli tarayici (Aşama 7).
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(marketCategoryProvider);
    final quotes = ref.watch(marketQuotesProvider);
    final viewMode = ref.watch(marketViewModeProvider);

    // Dinamik kategori listesi: AssetCategory enum'indan, katalogda varlığı olanlar.
    // CategoryNavSection (ana sayfa) ile birebir aynı mantık.
    final categoryEntries = <(AssetCategory, int, List<AssetDescriptor>)>[];
    for (var i = 0; i < AssetCategory.values.length; i++) {
      final cat = AssetCategory.values[i];
      final assets = AssetCatalog.byCategory(cat);
      if (assets.isNotEmpty) {
        categoryEntries.add((cat, i, assets));
      }
    }

    // Seçili index'in geçerli olup olmadığını kontrol et (katalog değişirse).
    final validIndices = categoryEntries.map((e) => e.$2).toSet();
    final safeIndex = validIndices.contains(index) ? index : (categoryEntries.isNotEmpty ? categoryEntries.first.$2 : 0);
    final categoryLabels = categoryEntries.map((e) => e.$1.label).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(
          title: 'Piyasalar',
          subtitle: categoryLabels.join(', '),
        ),
        const _SearchField(),
        CategoryChipBar(
          labels: categoryLabels,
          selectedIndex: categoryEntries.indexWhere((e) => e.$2 == safeIndex),
          onSelected: (i) =>
              ref.read(marketCategoryProvider.notifier).select(categoryEntries[i].$2),
        ),
        _ViewModeToggle(viewMode: viewMode),
        const SizedBox(height: 4),
        Expanded(
          child: _AssetList(
            categoryIndex: safeIndex,
            quotes: quotes,
            viewMode: viewMode,
            onRetry: () => ref.read(marketQuotesProvider.notifier).refresh(),
          ),
        ),
      ],
    );
  }
}

class _AssetList extends ConsumerWidget {
  const _AssetList({
    required this.categoryIndex,
    required this.quotes,
    required this.viewMode,
    required this.onRetry,
  });

  final int categoryIndex;
  final AsyncValue<Map<String, Quote>> quotes;
  final MarketViewMode viewMode;
  final VoidCallback onRetry;

  // AssetCategory enum indeksine göre kategori getir (katalogda varlığı olanlar).
  static AssetCategory _categoryForIndex(int index) {
    var catIndex = 0;
    for (var i = 0; i < AssetCategory.values.length; i++) {
      final cat = AssetCategory.values[i];
      final assets = AssetCatalog.byCategory(cat);
      if (assets.isNotEmpty) {
        if (catIndex == index) return cat;
        catIndex++;
      }
    }
    // Fallback: ilk dolu kategori
    for (var i = 0; i < AssetCategory.values.length; i++) {
      final cat = AssetCategory.values[i];
      if (AssetCatalog.byCategory(cat).isNotEmpty) return cat;
    }
    return AssetCategory.borsa;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(marketSearchProvider).trim();
    final searching = query.isNotEmpty;
    final category = _categoryForIndex(categoryIndex);

    // Arama yapiliyorsa **tum katalog** taranir (kullanici "USD/TRY"
    // yazarken "Döviz" sekmesinde olmak zorunda degil); yoksa kategori.
    final List<AssetDescriptor> pool;
    if (searching) {
      final q = _normalize(query);
      pool = [
        for (final a in AssetCatalog.all)
          if (_normalize(a.name).contains(q) ||
              _normalize(a.symbol).contains(q))
            a,
      ];
    } else {
      pool = AssetCatalog.byCategory(category);
    }

    if (pool.isEmpty) {
      return EmptyStateView(
        message: searching
            ? '"$query" ile eşleşen varlık bulunamadı.'
            : 'Bu kategoride henüz tanımlı varlık yok.',
        icon: searching ? Icons.search_off_rounded : Icons.category_outlined,
      );
    }

    final view = toViewState<Map<String, Quote>>(
      quotes,
      isEmpty: (m) => m.isEmpty,
    );

    return StateView<Map<String, Quote>>(
      state: view,
      onRetry: onRetry,
      emptyMessage: 'Fiyat verisi alınamadı.',
      builder: (map) {
        final visible = [
          for (final a in pool)
            if (map.containsKey(a.id)) a,
        ];
        // Fiyati henuz yuklenmemis varliklari da goster (placeholder ile).
        // Pool'daki varliklardan map'te olmayanlari da ekle (placeholder ile goster).
        final allVisible = [
          for (final a in pool)
            if (map.containsKey(a.id)) a else a,
        ];
        // Eger hicbiri map'te yoksa ve arama yoksa empty state goster.
        if (!searching && allVisible.every((a) => !map.containsKey(a.id))) {
          return EmptyStateView(
            message: 'Bu kategoride fiyat verisi yükleniyor...',
            icon: Icons.hourglass_empty_rounded,
          );
        }
        // Map'te olmayanlar sona eklensin (placeholder ile gosterilecek).
        final visibleSorted = [
          ...allVisible.where((a) => map.containsKey(a.id)),
          ...allVisible.where((a) => !map.containsKey(a.id)),
        ];

        if (viewMode == MarketViewMode.grid) {
          return _buildGrid(visible, map, searching, ref);
        }
        return _buildList(visible, map, searching, ref);
      },
    );
  }

  Widget _buildList(List<AssetDescriptor> visible, Map<String, Quote> map, bool searching, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(marketQuotesProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final asset = visible[i];
          final q = map[asset.id] ?? _placeholderQuote(asset);
          return QuoteCard(
            assetId: asset.id,
            quote: q,
            showSpread: asset.category == AssetCategory.doviz,
            trailing: WatchStar(assetId: asset.id, size: 20),
            onTap: () => openAssetDetail(context, asset.id),
          );
        },
      ),
    );
  }

  Quote _placeholderQuote(AssetDescriptor asset) {
    return Quote(
      assetId: asset.id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime.now(),
      price: null,
      currency: asset.currency,
      freshness: DataFreshness.unknown,
    );
  }

  Widget _buildGrid(List<AssetDescriptor> visible, Map<String, Quote> map, bool searching, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(marketQuotesProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth < 600
              ? 2
              : (constraints.maxWidth / 180).floor().clamp(2, 6);
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 180,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= visible.length) {
                        return const SizedBox.shrink();
                      }
                      final asset = visible[index];
                      final q = map[asset.id] ?? _placeholderQuote(asset);
                      return QuoteCard(
                        assetId: asset.id,
                        quote: q,
                        showSpread: asset.category == AssetCategory.doviz,
                        trailing: WatchStar(assetId: asset.id, size: 20),
                        onTap: () => openAssetDetail(context, asset.id),
                      );
                    },
                    childCount: visible.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Varlik arama kutusu.
///
/// Metin [marketSearchProvider]'da yasar; listeyle dogrudan baglidir
/// (yeni her harfde tam yeniden kurulum yerine yalnizca liste filtresi
/// degisir).
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _ctrl;
  var _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(marketSearchProvider));
    _hasText = _ctrl.text.isNotEmpty;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _publish(String value) {
    ref.read(marketSearchProvider.notifier).set(value);
    if (mounted) setState(() => _hasText = value.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _ctrl,
        onChanged: _publish,
        style: theme.textTheme.bodyMedium,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Varlık ara (ör. gram altın, dolar)',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _hasText
              ? IconButton(
                  tooltip: 'Aramayı temizle',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _ctrl.clear();
                    _publish('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}

/// Turkce arama normalizasyonu: "altin" yazinca "Altın", "usd" yazinca
/// "USD" bulunur. Buyuk/kucuk harf ve Turkce ozel karakterler esitlenir.
String _normalize(String s) {
  const specials = <String, String>{
    'ı': 'i', 'İ': 'i',
    'ş': 's', 'Ş': 's',
    'ğ': 'g', 'Ğ': 'g',
    'ç': 'c', 'Ç': 'c',
    'ö': 'o', 'Ö': 'o',
    'ü': 'u', 'Ü': 'u',
  };
  final buf = StringBuffer();
  for (final r in s.runes) {
    final raw = String.fromCharCode(r);
    final direct = specials[raw];
    if (direct != null) {
      buf.write(direct);
      continue;
    }
    final lower = raw.toLowerCase();
    buf.write(specials[lower] ?? lower);
  }
  return buf.toString();
}


/// Izgara / Liste gorunum degistirici.
class _ViewModeToggle extends ConsumerWidget {
  const _ViewModeToggle({required this.viewMode});

  final MarketViewMode viewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            viewMode.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<MarketViewMode>(
            segments: [
              ButtonSegment<MarketViewMode>(
                value: MarketViewMode.grid,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                tooltip: 'Izgara',
              ),
              ButtonSegment<MarketViewMode>(
                value: MarketViewMode.list,
                icon: const Icon(Icons.view_agenda_outlined, size: 18),
                tooltip: 'Liste',
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (Set<MarketViewMode> selection) {
              ref.read(marketViewModeProvider.notifier).setView(selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            ),
          ),
        ],
      ),
    );
  }
}