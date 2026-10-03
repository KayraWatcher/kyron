import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/economic_event.dart';
import '../../shared/widgets/common.dart';
import 'calendar_providers.dart';

/// Ekonomik Takvim (Aşama 13).
///
/// **Kural:** Veri yoksa UYDURMA. Takvim saglayicisi baglanana kadar
/// ekranda "veri yok" durumu gosterilir; sahte olay, sahte beklenti veya
/// sahte "Gerceklesen" degeri asla yazilmaz.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarEventsProvider);
    final range = ref.watch(calendarRangeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenTitle(
          title: 'Takvim',
          subtitle: 'Ekonomik olaylar ve şirket duyuruları',
        ),
        CategoryChipBar(
          labels: const ['Bugün', 'Bu Hafta', 'Bu Ay'],
          selectedIndex: range,
          onSelected: (i) {
            ref.read(calendarRangeProvider.notifier).select(i);
            ref.read(calendarEventsProvider.notifier).refresh();
          },
        ),
        const SizedBox(height: 4),
        Expanded(
          child: switch (state) {
            CalendarLoading() => const _Loading(),
            CalendarError(:final message) => _ErrorView(message: message),
            CalendarReady(:final events) =>
              events.isEmpty ? const _Empty() : _EventList(events: events),
          },
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 42, color: AppPalette.loss),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
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
            Icon(Icons.event_available_rounded,
                size: 46, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              'Veri kaynağına henüz bağlanılamadı',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Ekonomik takvim verileri (TCMB/PPK, TÜİK enflasyon-işsizlik-'
              'GSYH, cari açık, şirket bilançoları) sağlanıcı bağlandığında '
              'burada görünecek.\n\n'
              'Eksik veri asla tamamlanmaz: beklenti, önceki ve gerçekleşen '
              'değerler yalnızca kaynaktan alınır; yoksa "—" gösterilir.',
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

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<EconomicEvent> events;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _EventTile(event: events[i]),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final EconomicEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _importanceDot(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _when,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.neutral),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            event.country,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cell(context, 'Beklenti', event.forecast),
              _cell(context, 'Önceki', event.previous),
              _cell(context, 'Gerçekleşen', event.actual),
            ],
          ),
        ],
      ),
    );
  }

  String get _when {
    final d = event.date;
    final t = event.time;
    final date =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    if (t == null) return date;
    return '$date ${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _cell(BuildContext context, String label, String? value) {
    final theme = Theme.of(context);
    // Veri yoksa kesinlikle "0" veya tahmin YAZILMAZ; "—" gosterilir.
    final shown = (value == null || value.isEmpty) ? null : value;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppPalette.neutral, fontSize: 10.5)),
          const SizedBox(height: 2),
          Text(
            shown ?? '—',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color:
                  shown == null ? AppPalette.neutral : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// 1=yuksek 2=orta 3=dusuk  |  null=onem belirtilmemis
  Widget _importanceDot() {
    final imp = event.importance;
    final color = switch (imp) {
      3 => AppPalette.loss,
      2 => AppPalette.gold,
      1 => AppPalette.neutral,
      _ => AppPalette.neutral,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
