import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset_catalog.dart';
import 'home_display.dart';

/// Ana sayfa "Piyasalar" listesi icin **filtre + siralama** alt sayfasi.
///
/// * Filtre: Öne çıkanlar / Tümü / Borsa / Altın / Gümüş / Döviz / Fonlar /
///   Takip edilenler
/// * Siralama: Varsayilan / Fiyat / Günlük değişim % / Değişim miktarı /
///   Alış / Satış + yon (Artan / Azalan)
/// * Kisayollar: En çok yükselen / En çok düşen
///
/// Secimler [homeDisplayProvider] uzerinden tutulur; liste **yeniden
/// siralanirken kullanici bir karti tutuyorsa dokunma kilidi devreye girer**
/// (bkz. `TouchLockedOrder`).
Future<void> showHomeDisplaySheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _HomeDisplaySheet(),
  );
}

class _HomeDisplaySheet extends ConsumerWidget {
  const _HomeDisplaySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(homeDisplayProvider);
    final notifier = ref.read(homeDisplayProvider.notifier);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Filtre ve sıralama', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Sıralama, verisi gelmeyen varlıkları en sona koyar; '
                'eksik değer asla 0 sayılmaz.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppPalette.neutral, height: 1.4),
              ),
              const SizedBox(height: 18),

              // ---------------------------------------------------------------------------
              // Filtre
              // ---------------------------------------------------------------------------
              Text('Filtre', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in HomeFilter.values)
                    _ChoicePill(
                      label: f.label,
                      selected: state.filter == f,
                      onTap: () => notifier.setFilter(f),
                    ),
                ],
              ),

              const SizedBox(height: 22),

              // ---------------------------------------------------------------------------
              // Gorunum
              // ---------------------------------------------------------------------------
              Text('Görünüm', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ChoicePill(
                      label: 'Izgara (2 sütun)',
                      selected: state.view == HomeViewMode.grid,
                      onTap: () => notifier.setView(HomeViewMode.grid),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChoicePill(
                      label: 'Liste (tek sütun)',
                      selected: state.view == HomeViewMode.list,
                      onTap: () => notifier.setView(HomeViewMode.list),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ---------------------------------------------------------------------------
              // One cikanlar (kullaniciya ozel)
              // ---------------------------------------------------------------------------
              Text('Öne çıkanlar', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Ana sayfada "Öne çıkanlar" filtresinde gösterilecek '
                'varlıklar ve sırası. Eklediğiniz her şey kaydedilir; '
                'uygulama yeniden açılsa da korunur.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppPalette.neutral, height: 1.4),
              ),
              const SizedBox(height: 10),
              if (state.pinned.isEmpty)
                Text(
                  'Öne çıkan varlık yok. Aşağıdan ekleyin.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppPalette.neutral),
                )
              else
                for (var i = 0; i < state.pinned.length; i++)
                  _PinRow(
                    index: i,
                    assetId: state.pinned[i],
                    isFirst: i == 0,
                    isLast: i == state.pinned.length - 1,
                    onUp: () => notifier.pinMove(state.pinned[i], -1),
                    onDown: () => notifier.pinMove(state.pinned[i], 1),
                    onRemove: () => notifier.pinRemove(state.pinned[i]),
                  ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: notifier.pinCandidates.isEmpty
                    ? null
                    : () => _showAddPinnedSheet(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Varlık ekle'),
              ),

              const SizedBox(height: 22),

              // ---------------------------------------------------------------------------
              // Kisayollar
              // ---------------------------------------------------------------------------
              Text('Hızlı sıralama', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChoicePill(
                    label: '↑ En çok yükselen',
                    selected: state.sort == HomeSortField.degisimYuzde &&
                        !state.ascending,
                    onTap: () => notifier.setQuickRising(rising: true),
                  ),
                  _ChoicePill(
                    label: '↓ En çok düşen',
                    selected: state.sort == HomeSortField.degisimYuzde &&
                        state.ascending,
                    onTap: () => notifier.setQuickRising(rising: false),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ---------------------------------------------------------------------------
              // Siralama alani
              // ---------------------------------------------------------------------------
              Text('Sıralama ölçütü', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final s in HomeSortField.values)
                _RadioRow(
                  label: s.label,
                  selected: state.sort == s,
                  onTap: () => notifier.setSort(
                    s,
                    ascending: s == HomeSortField.varsayilan
                        ? true
                        : state.ascending,
                  ),
                ),

              const SizedBox(height: 12),

              // ---------------------------------------------------------------------------
              // Yon
              // ---------------------------------------------------------------------------
              Text('Yön', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ChoicePill(
                      label: 'Artan (↑ küçükten büyüğe)',
                      selected: state.ascending,
                      enabled: state.sort != HomeSortField.varsayilan,
                      onTap: () => notifier.setSort(
                        state.sort,
                        ascending: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChoicePill(
                      label: 'Azalan (↓ büyükten küçüğe)',
                      selected: !state.ascending,
                      enabled: state.sort != HomeSortField.varsayilan,
                      onTap: () => notifier.setSort(
                        state.sort,
                        ascending: false,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isDefault
                          ? null
                          : () => notifier.reset(),
                      child: const Text('Sıfırla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Tamam'),
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

/// "Öne çıkanlar" satiri: sira tuslari + kaldirma.
class _PinRow extends StatelessWidget {
  const _PinRow({
    required this.index,
    required this.assetId,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int index;
  final String assetId;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = AssetCatalog.byId(assetId)?.name ?? assetId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppPalette.neutral),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Yukarı taşı',
            visualDensity: VisualDensity.compact,
            onPressed: isFirst ? null : onUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
          ),
          IconButton(
            tooltip: 'Aşağı taşı',
            visualDensity: VisualDensity.compact,
            onPressed: isLast ? null : onDown,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
          ),
          IconButton(
            tooltip: 'Öne çıkarılanlardan kaldır',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppPalette.loss,
          ),
        ],
      ),
    );
  }
}

/// Henuz one cikan olmayan varliklardan secim yapilan alt sayfa.
Future<void> _showAddPinnedSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Öne çıkan varlık ekle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final id
                in ref.read(homeDisplayProvider.notifier).pinCandidates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AssetCatalog.byId(id)?.name ?? id),
                subtitle: Text(
                  AssetCatalog.byId(id)?.symbol ?? '',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.neutral,
                      ),
                ),
                trailing: const Icon(Icons.add_circle_outline_rounded),
                onTap: () {
                  ref.read(homeDisplayProvider.notifier).pinAdd(id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? AppPalette.neutral
        : selected
            ? AppPalette.gold
            : theme.colorScheme.outline;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.gold.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: selected ? 1.6 : 1),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected ? AppPalette.gold : null,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? AppPalette.gold : AppPalette.neutral,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected ? AppPalette.gold : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
