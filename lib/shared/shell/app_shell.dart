import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// Alt navigasyondaki 5 ana bolum.
enum AppSection {
  home('Ana Sayfa', Icons.home_rounded),
  markets('Piyasalar', Icons.show_chart_rounded),
  portfolio('Portföy', Icons.account_balance_wallet_rounded),
  news('Haberler', Icons.newspaper_rounded),
  calendar('Takvim', Icons.event_note_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Alt navigasyonun hangi sekmede oldugunu tutan provider.
final selectedSectionProvider =
    NotifierProvider<SelectedSectionNotifier, AppSection>(
  SelectedSectionNotifier.new,
);

class SelectedSectionNotifier extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.home;

  void select(AppSection section) => state = section;
}

/// Uygulama kabugu: alt navigasyon + bolum govdesi.
///
/// Her bolum kendi durumunu yonetir; kabuk yalnizca secimi tutar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.children});

  /// [AppSection.index] ile eslesen bolum govdesi.
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSectionProvider);
    final index = selected.index;

    return Scaffold(
      // Basliklar status bar'in altinda kalmasin; alt navigasyon zaten
      // Scaffold tarafindan disarida tutuluyor, alt pay eklenmez.
      body: SafeArea(
        top: true,
        bottom: false,
        child: IndexedStack(
          index: index,
          children: children,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedSectionProvider.notifier).select(
                  AppSection.values[i],
                ),
        destinations: [
          for (final s in AppSection.values)
            NavigationDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.icon),
              label: s.label,
            ),
        ],
      ),
    );
  }
}

/// Ana ekrana donme tetikleyicisi (varlik detayindan geri gelince
/// dogru sekmede kalmak icin kullanilir).
void selectSection(WidgetRef ref, AppSection section) {
  ref.read(selectedSectionProvider.notifier).select(section);
}

/// Simge rengi: yon bilgisi varsa renklenir.
Color directionColor(BuildContext context, double? value) =>
    AppPalette.direction(value);
