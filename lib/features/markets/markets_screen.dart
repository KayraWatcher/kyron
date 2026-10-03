import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/navigator_utils.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/quote_card.dart';
import '../../shared/widgets/watch_star.dart';
import 'markets_providers.dart';

/// Piyasalar - kategori bazli tarayici (Aşama 7).
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  static const List<String> _categories = [
    'Borsa',
    'Altın',
    'Gümüş',
    'Döviz',
    'Fonlar',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(marketCategoryProvider);
    final quotes = ref.watch(marketQuotesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenTitle(
          title: 'Piyasalar',
          subtitle: 'Borsa, altın, gümüş, döviz ve fonlar',
        ),
        const _SearchField(),
        CategoryChipBar(
          labels: _categories,
          selectedIndex: index,
          onSelected: (i) =>
              ref.read(marketCategoryProvider.notifier).select(i),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _AssetList(
            categoryIndex: index,
            quotes: quotes,
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
    required this.onRetry,
  });

  final int categoryIndex;
  final AsyncValue<Map<String, Quote>> quotes;
  final VoidCallback onRetry;

  static const List<AssetCategory> _map = [
    AssetCategory.borsa,
    AssetCategory.altin,
    AssetCategory.gumus,
    AssetCategory.doviz,
    AssetCategory.fon,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(marketSearchProvider).trim();
    final searching = query.isNotEmpty;
    final category = _map[categoryIndex];

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
        if (visible.isEmpty) {
          return EmptyStateView(
            message: searching
                ? '"$query" için fiyat verisi bulunamadı.'
                : 'Bu kategoride fiyat verisi bulunamadı.',
            icon: Icons.search_off_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(marketQuotesProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visible.length + _footerCount(visible.length),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i >= visible.length) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _SourceNote(),
                );
              }
              final asset = visible[i];
              final q = map[asset.id]!;
              return QuoteCard(
                assetId: asset.id,
                quote: q,
                showSpread: asset.category == AssetCategory.doviz,
                // Takip listesi (favori) - kalıcı, tum ekranlarda ortak.
                trailing: WatchStar(assetId: asset.id, size: 20),
                onTap: () => openAssetDetail(context, asset.id),
              );
            },
          ),
        );
      },
    );
  }

  int _footerCount(int n) => n > 0 ? 1 : 0;
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

class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Veri kaynakları',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• Döviz kurları: TCMB resmi günlük kurları.\n'
            '• Borsa ve ons metaller: Yahoo Finance piyasa verisi.\n'
            '• "Hesaplanan" etiketli varlıklar (gram altın, çeyrek vb.) '
            'bileşenlerden matematiksel olarak türetilir; serbest piyasa '
            'fiyatı değildir.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
