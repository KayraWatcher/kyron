import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../charts/chart_types.dart';
import '../asset_detail_providers.dart';

/// Gosterge ekleme / duzenleme sayfasi.
Future<void> showIndicatorSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _IndicatorSheet(),
  );
}

class _IndicatorSheet extends ConsumerWidget {
  const _IndicatorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = ref.watch(activeIndicatorsProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Göstergeler',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (active.isNotEmpty)
                    TextButton(
                      onPressed: () => ref
                          .read(activeIndicatorsProvider.notifier)
                          .clear(),
                      child: const Text('Tümünü kaldır'),
                    ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final d in IndicatorPresets.all)
                    _IndicatorTile(descriptor: d),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicatorTile extends ConsumerWidget {
  const _IndicatorTile({required this.descriptor});

  final IndicatorDescriptor descriptor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = ref.watch(activeIndicatorsProvider);
    final current = active.where((e) => e.id == descriptor.id).firstOrNull;
    final isEnabled = current != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? theme.colorScheme.primary
              : (theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  descriptor.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _PaneBadge(pane: descriptor.pane),
            ],
          ),
          subtitle: current == null
              ? null
              : Text(
                  current.params.entries
                      .map((e) => '${e.key}: ${_fmt(e.value)}')
                      .join('  '),
                  style: theme.textTheme.labelSmall,
                ),
          trailing: Switch(
            value: isEnabled,
            onChanged: (v) {
              final n = ref.read(activeIndicatorsProvider.notifier);
              if (v) {
                n.add(IndicatorPresets.make(descriptor.id));
              } else {
                n.remove(descriptor.id);
              }
            },
          ),
          children: [
            if (isEnabled && descriptor.paramKeys.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  children: [
                    for (final key in descriptor.paramKeys)
                      _ParamRow(descriptor: descriptor, paramKey: key),
                  ],
                ),
              )
            else if (isEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'Bu göstergenin ayarlanabilir parametresi yok.',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppPalette.neutral),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
}

class _ParamRow extends ConsumerWidget {
  const _ParamRow({required this.descriptor, required this.paramKey});

  final IndicatorDescriptor descriptor;
  final String paramKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = ref.watch(activeIndicatorsProvider);
    final current =
        active.where((e) => e.id == descriptor.id).firstOrNull;
    if (current == null) return const SizedBox.shrink();

    final value = current.params[paramKey] ?? descriptor.defaults[paramKey]!;
    final min = _minFor(paramKey, descriptor.defaults[paramKey]!);
    final max = _maxFor(paramKey, descriptor.defaults[paramKey]!);
    final isInt = paramKey != 'dev';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              _label(paramKey),
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: isInt ? (max - min).round() : null,
              label: isInt ? value.round().toString() : value.toStringAsFixed(2),
              onChanged: (v) => ref
                  .read(activeIndicatorsProvider.notifier)
                  .setParam(descriptor.id, paramKey, v),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              isInt ? value.round().toString() : value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _label(String k) => switch (k) {
        'period' => 'Periyot',
        'fast' => 'Hızlı',
        'slow' => 'Yavaş',
        'signal' => 'Sinyal',
        'smooth' => 'Yumuşatma',
        'dev' => 'Std. Sapma',
        _ => k,
      };

  double _minFor(String k, double def) => switch (k) {
        'dev' => 1,
        'fast' => 2,
        'slow' => 5,
        'signal' => 2,
        'smooth' => 1,
        'period' => 2,
        _ => 2,
      };

  double _maxFor(String k, double def) => switch (k) {
        'dev' => 5,
        'fast' => 50,
        'slow' => 100,
        'signal' => 50,
        'smooth' => 20,
        'period' => 200,
        _ => 200,
      };
}

class _PaneBadge extends StatelessWidget {
  const _PaneBadge({required this.pane});

  final IndicatorPane pane;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (pane) {
      IndicatorPane.overlay => ('Fiyat üzerinde', AppPalette.gold),
      IndicatorPane.oscillator =>
        ('Ayrı panel', const Color(0xFF3B82F6)),
      IndicatorPane.zeroBased =>
        ('Sıfır merkezli', const Color(0xFF8B5CF6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
