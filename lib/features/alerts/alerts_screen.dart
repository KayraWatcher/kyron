import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/price_alert.dart';
import 'alert_providers.dart';
import 'alert_sheet.dart';
import 'notification_service.dart';

/// Alarmlar ekrani (Aşama 14).
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alerts = ref.watch(alertsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Alarmlar'),
        actions: [
          if (alerts.isNotEmpty)
            IconButton(
              tooltip: 'Tümünü sil',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: alerts.isEmpty
            ? const _Empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  const _PermissionBanner(),
                  for (final a in alerts) _AlertTile(alert: a),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAlertSheet(context),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Alarm oluştur'),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm alarmlar silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(alertsProvider.notifier).removeAll();
    }
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enabled = ref.watch(notificationsEnabledProvider);

    return switch (enabled) {
      AsyncData(value: true) => const SizedBox.shrink(),
      AsyncData(value: false) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.loss.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.loss.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_off_rounded,
                  color: AppPalette.loss, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bildirimler kapalı. Alarmlar çalışır ancak bildirim '
                  'göremezsiniz.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await NotificationService.requestPermission();
                  ref.invalidate(notificationsEnabledProvider);
                },
                child: const Text('İzin ver'),
              ),
            ],
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final PriceAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asset = alert.assetId == null ? null : AssetCatalog.byId(alert.assetId!);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.enabled
              ? (theme.dividerTheme.color ?? Colors.grey)
              : AppPalette.neutral.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (alert.enabled ? AppPalette.gold : AppPalette.neutral)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _icon(alert.type),
              size: 18,
              color: alert.enabled ? AppPalette.goldDeep : AppPalette.neutral,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset?.name ??
                      (alert.type == AlertType.importantNews
                          ? 'Önemli haber'
                          : alert.assetId ?? '—'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _condition,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (alert.triggeredAt != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 13, color: AppPalette.gain),
                      const SizedBox(width: 4),
                      Text(
                        'Tetiklendi · ${TrFormat.dateTime(alert.triggeredAt)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppPalette.gain),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: alert.enabled,
            onChanged: (v) =>
                ref.read(alertsProvider.notifier).setEnabled(alert.id, v),
          ),
          IconButton(
            tooltip: 'Sil',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: theme.colorScheme.onSurfaceVariant),
            onPressed: () =>
                ref.read(alertsProvider.notifier).remove(alert.id),
          ),
        ],
      ),
    );
  }

  String get _condition {
    switch (alert.type) {
      case AlertType.priceAbove:
        return 'Fiyat ${TrFormat.money(alert.threshold)} üzerine çıkarsa';
      case AlertType.priceBelow:
        return 'Fiyat ${TrFormat.money(alert.threshold)} altına inerse';
      case AlertType.percentChange:
        // Not: `TrFormat.percent` zaten "%1,42" dondurur; % burada elle
        // eklenirse cift % olurdu (" %+%+1,42"). Isaret yonde gore verilir.
        final sign = alert.direction == AlertDirection.above ? '+' : '-';
        return 'Değişim %$sign'
            '${TrFormat.percent(alert.percent?.abs(), withSign: false)} '
            'olursa';
      case AlertType.dayHigh:
        return 'Günün en yüksek seviyesine ulaşırsa';
      case AlertType.dayLow:
        return 'Günün en düşük seviyesine ulaşırsa';
      case AlertType.importantNews:
        final c = alert.newsCategory;
        return c == null || c.isEmpty
            ? 'Yeni önemli haber geldiğinde'
            : 'Yeni "$c" haber geldiğinde';
    }
  }

  IconData _icon(AlertType t) => switch (t) {
        AlertType.priceAbove => Icons.trending_up_rounded,
        AlertType.priceBelow => Icons.trending_down_rounded,
        AlertType.percentChange => Icons.percent_rounded,
        AlertType.dayHigh => Icons.vertical_align_top_rounded,
        AlertType.dayLow => Icons.vertical_align_bottom_rounded,
        AlertType.importantNews => Icons.newspaper_rounded,
      };
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 46, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              'Henüz alarm yok',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Bir varlık fiyatını, değişim oranını veya gün içi en yüksek-'
              'en düşük seviyesini takip etmek için alarm oluşturabilirsiniz.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
