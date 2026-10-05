import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset_catalog.dart';

/// Secim listesindeki bir varligin **sira satiri**: numara · ad ·
/// yukari/asagi tasima · kaldirma.
///
/// "Filtre ve siralama" sayfasindaki ("Öne çıkanlar") satir ile **ayni
/// desendir**; iki sayfa ayni component'i paylasir (kopya satir olusturulmaz).
class OrderableAssetRow extends StatelessWidget {
  const OrderableAssetRow({
    super.key,
    required this.index,
    required this.assetId,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
    this.removeTooltip = 'Listeden kaldır',
  });

  final int index;
  final String assetId;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  /// Kaldirma ikonunun ipucu (sayfaya gore metin farkli olabilir).
  final String removeTooltip;

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
            tooltip: removeTooltip,
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

/// Henuz secilmemis katalog varliklarindan secim yapilan **alt sayfa**.
///
/// [onAdd] yalnizca uygulamanin mevcut canonical id'lerini alir; sayfa
/// uydurma varlik uretmez.
Future<void> showAddAssetSheet(
  BuildContext context, {
  required String title,
  required List<String> candidateIds,
  required void Function(String assetId) onAdd,
}) {
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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final id in candidateIds)
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
                  onAdd(id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}
