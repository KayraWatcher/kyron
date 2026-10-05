import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset_catalog.dart';
import 'asset_selection_sheet.dart';
import 'away_changes_provider.dart';

/// "Sen Yokken Ne Oldu?" bolumu icin **varlik secimi** alt sayfasi.
///
/// * Yalnizca [AssetCatalog] canonical id'leri secilebilir (uydurma yok).
/// * Eklemek / kaldirmak / siralamak [awaySelectionProvider] uzerinden
///   kalici olarak kaydedilir; uygulama yeniden acilsa da korunur.
/// * En fazla [awaySelectionMax] varlik; varsayilan Gram + Ceyrek'tir.
Future<void> showAwaySelectionSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _AwaySelectionSheet(),
  );
}

class _AwaySelectionSheet extends ConsumerWidget {
  const _AwaySelectionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(awaySelectionProvider);
    final notifier = ref.read(awaySelectionProvider.notifier);
    final atMax = selection.length >= awaySelectionMax;
    final candidates = notifier.candidates;

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
              Text('Sen Yokken Ne Oldu?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Bu bölüme gösterilecek varlıklar ve sıra. En fazla '
                '$awaySelectionMax varlık; seçim kaydedilir, uygulama yeniden '
                'açılsa da korunur.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.neutral,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (selection.isEmpty)
                Text(
                  'Varlık yok. Aşağıdan ekleyin.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppPalette.neutral,
                  ),
                )
              else
                for (var i = 0; i < selection.length; i++)
                  OrderableAssetRow(
                    index: i,
                    assetId: selection[i],
                    isFirst: i == 0,
                    isLast: i == selection.length - 1,
                    onUp: () => notifier.move(selection[i], -1),
                    onDown: () => notifier.move(selection[i], 1),
                    onRemove: () => notifier.remove(selection[i]),
                    removeTooltip: 'Seçimden kaldır',
                  ),
              const SizedBox(height: 8),
              if (atMax)
                Text(
                  'En fazla $awaySelectionMax varlık gösterilebilir; eklemek '
                  'için birini kaldırın.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.neutral,
                    height: 1.4,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: candidates.isEmpty
                      ? null
                      : () => showAddAssetSheet(
                            context,
                            title: 'Varlık ekle',
                            candidateIds: candidates,
                            onAdd: notifier.add,
                          ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Varlık ekle'),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: notifier.isDefault ? null : notifier.reset,
                      child: const Text('Varsayılana dön'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
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
