import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/state_view.dart';

/// Ortak baslik bicimi - tum ekranlarda tutarlilik saglar.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 10),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (action != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  action!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ekran basligi - AppBar disinda govde ustu icin.
class ScreenTitle extends ConsumerWidget {
  const ScreenTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kategori/secim cipleri.
class CategoryChipBar extends StatelessWidget {
  const CategoryChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return ChoiceChip(
            label: Text(labels[i]),
            selected: selected,
            onSelected: (_) => onSelected(i),
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
      ),
    );
  }
}

/// `CustomScrollView`/`SliverList` icinde kullanilan durum gosterimi.
///
/// Yukleme/hata/bos durumlarinda tek bir Sliver dondurulur; hazir oldugunda
/// [sliverBuilder] cagrilir. Boylece ekranlarin kaydirma yapisi bozulmaz.
class StateSliver<T> extends StatelessWidget {
  const StateSliver({
    super.key,
    required this.state,
    required this.onRetry,
    required this.sliverBuilder,
    this.emptyMessage,
    this.emptyIcon,
    this.loadingSliver,
  });

  final ViewState<T> state;
  final VoidCallback onRetry;
  final Widget Function(T data) sliverBuilder;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final Widget? loadingSliver;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return switch (s) {
      Loading<T>() =>
        loadingSliver ?? const SliverToBoxAdapter(child: LoadingStateView()),
      Failed<T>(:final failure) => SliverToBoxAdapter(
          child: ErrorStateView(failure: failure, onRetry: onRetry),
        ),
      Empty<T>(:final message) => SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView(
            message: emptyMessage ?? message,
            icon: emptyIcon ?? Icons.inbox_rounded,
          ),
        ),
      Ready<T>(:final data) => sliverBuilder(data),
    };
  }
}

/// `ListView.builder` benzeri yerlesimlerde kullanilan tek satirlik sarici.
///
/// Boylece ekranlar `StateView` ile ayni durum modelini paylasir.
class StateBox<T> extends StatelessWidget {
  const StateBox({
    super.key,
    required this.state,
    required this.onRetry,
    required this.builder,
    this.emptyMessage,
    this.emptyIcon,
    this.loadingWidget,
  });

  final ViewState<T> state;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final Widget? loadingWidget;

  @override
  Widget build(BuildContext context) {
    return StateView<T>(
      state: state,
      onRetry: onRetry,
      builder: builder,
      emptyMessage: emptyMessage,
      emptyIcon: emptyIcon,
      child: loadingWidget,
    );
  }
}
