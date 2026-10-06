/// Update UI components.
///
/// Contains the dialogs and screens for optional/forced updates.
library update_ui;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_notifier.dart';
import 'version_compare.dart';
import '../providers/app_providers.dart';

/// Shows the optional update dialog if an update is available.
///
/// Returns `true` if the user chose to update, `false` if dismissed.
Future<bool?> showOptionalUpdateDialog(BuildContext context, UpdateCheckResult result) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OptionalUpdateDialog(result: result),
  );
}

/// Shows the forced update screen (cannot be dismissed).
///
/// Returns `true` if the user chose to update.
Future<bool?> showForcedUpdateScreen(BuildContext context, UpdateCheckResult result) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ForcedUpdateScreen(result: result),
  );
}

/// Optional update dialog widget.
class _OptionalUpdateDialog extends ConsumerWidget {
  const _OptionalUpdateDialog({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.system_update_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Yeni sürüm mevcut',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'KYRON ${result.latestVersion} sürümü yayınlandı.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mevcut sürüm: ${result.currentVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Daha Sonra'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.of(context).pop(true);
                      await _launchUrl(ref);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Güncelle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(WidgetRef ref) async {
    // Track download click telemetry
    unawaited(ref.read(telemetryProvider).trackUpdateDownloadClicked(forced: false));

    const url = 'https://kayrawatcher.github.io/kyron-web/';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

/// Forced update screen widget (cannot be dismissed).
class _ForcedUpdateScreen extends ConsumerWidget {
  const _ForcedUpdateScreen({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Prevent back button dismiss
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Güncelleme gerekli',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'KYRON\'u kullanmaya devam etmek için '
                'uygulamanın yeni sürümünü (${result.latestVersion}) yüklemelisin.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mevcut sürüm: ${result.currentVersion} — Minimum: ${result.minimumVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    // ZORUNLU GUNCELLEME bu dialogu HICBIR KOSULDA
                    // programatik olarak kapatmaz.
                    //
                    // `launchUrl` true donse bile bu sadece "ACTION_VIEW intent'i
                    // gonderildi" demektir. Cihazda varsayilan tarayici
                    // atanmadiginda Android bir chooser ("Open with") acar ve
                    // kullanici onu CANCEL edebilir. Once `pop(true)` cagrildigi
                    // icin (bu satirin onceden hali) chooser iptal edildiginde
                    // kullanici KYRON'a dialog KAPALI halde donuyor ve uygulamayi
                    // engelsiz kullanabiliyordu.
                    //
                    // Cozum: dialogu kapatmayiz. Kullanicinin cikis yolu yalnizca
                    // uygulamayi gercekten guncelleyip yeniden baslatmaktir; o
                    // zaman check 'upToDate' doner ve dialog hic gosterilmez.
                    final launched = await _launchUrl(ref);
                    debugPrint(
                      '[UpdateUI] update URL denemesi sonucu: launched=$launched; '
                      'forced update dialogu AÇIK kalıyor.',
                    );
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Şimdi Güncelle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Update URL'sini acar.
  ///
  /// DIKKAT: [true] yalnizca "ACTION_VIEW intent'i basariyla gonderildi"
  /// demektir - tarayicinin GERCEKTEN acilip acilmadigini garanti ETMEZ.
  /// Android varsayilan tarayici atanmadiginda chooser acar; kullanici onu
  /// iptal ederse [true] donmus olsa bile uygulamaya donulur. Bu yuzden
  /// zorunlu guncelleme dialogu bu sonuca BAKARAK kapanmaz.
  ///
  /// Telemetri (`update_download_clicked`) her tiklamada bir kez gonderilir.
  Future<bool> _launchUrl(WidgetRef ref) async {
    // Track forced update shown when user interacts (first time)
    // The screen is already shown, so we track the click
    unawaited(ref.read(telemetryProvider).trackUpdateDownloadClicked(forced: true));

    const url = 'https://kayrawatcher.github.io/kyron-web/';
    final uri = Uri.parse(url);

    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[UpdateUI] update URL acilamadi, dialog acik kalacak. Detay: $e');
      return false;
    }
  }
}

/// Consumer widget that shows the appropriate update UI based on check result.
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  bool _checked = false;
  bool _dialogShown = false;
  bool _forcedUpdateTelemetrySent = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    if (_checked) return;
    _checked = true;

    // 1) ONCE dinleyiciyi kur, SONRA check'i tetikle.
    //
    // `checkForUpdates()` iki yerden tetiklenir (burasi ve
    // AppLifecycleBinder._checkForUpdates) ve `UpdateNotifier` basinda
    // `if (state.isLoading) return;` guari vardir. Yani check'in kim
    // tamamladigi cagri siralamasina baglidir ve "kaybeden" cagri aninda
    // doner. Onceki implementasyon yalnizca `await checkForUpdates()` sonrasi
    // TEK SEFERLIK `ref.read(...).result` okuyordu; check baska biri
    // tarafindan (veya daha once) tamamlanmissa `result` null idi, dialog
    // hic gosterilmiyordu ve HICBIR exception atilmadigi icin log da
    // gorunmuyordu.
    //
    // Dinleyici artik [build] icinde kurulur - bkz. [build] yorumu. Check'in
    // cevabi ag üzerinden geldigi icin dinleyici her zaman **cok once**
    // kayitli olur; asagidaki `ref.read` ise zaten hazir olan sonucu kapsar.
    // `_dialogShown` cift gosterimi engeller.
    try {
      await ref.read(updateNotifierProvider.notifier).checkForUpdates();

      // Check bu cagriyla bittiyse sonuc hazirdir; yine de dogrudan oku.
      if (!mounted) return;
      _presentResult(ref.read(updateNotifierProvider).result);
    } catch (e, st) {
      // Update check failed (e.g., test environment, no config): continue with
      // normal app startup. Artik sessizce yutulmuyor - gerekce loglanir,
      // boylece "dialog neden acilmadi?" sorusu 1 dakikada cevaplanir.
      debugPrint(
        '[UpdateChecker] update check istisna atti; uygulama normal sekilde '
        'devam ediyor. Detay: $e\n$st',
      );
    }
  }

  /// Update sonucunu tek noktadan degerlendirir ve uygun ekrani gosterir.
  ///
  /// [result] null ise (check henuz sonlanmadi) sessizce gec - [ref.listen]
  /// sonuc gelince zaten burayi cagiracak.
  void _presentResult(UpdateCheckResult? result) {
    if (!mounted || _dialogShown || result == null) return;

    if (result.isForcedUpdate) {
      _dialogShown = true;
      if (!_forcedUpdateTelemetrySent) {
        _forcedUpdateTelemetrySent = true;
        unawaited(ref.read(telemetryProvider).trackForcedUpdateShown());
      }
      showForcedUpdateScreen(context, result);
    } else if (result.isUpdateAvailable) {
      _dialogShown = true;
      showOptionalUpdateDialog(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `ref.listen` yalnizca `build` icinde cagrilabilir; `initState`'ten
    // cagrilmasi `debugDoingBuild` assertion'ini firlatiyordu (Riverpod 3).
    //
    // Etki: release build'de assertion'lar kapali oldugu icin uretimde
    // gorunmuyordu, ancak `widget_test.dart` (5 sekmeli kabuk) debug
    // modda **her zaman** fail oluyordu.
    //
    // Zamanlama degismez: `initState` asenkron check'i baslatir, bu
    // `build` ayni frame icinde hemen calisir; ag cevabi geldiginde
    // dinleyici zaten kayitlidir. Tekrarlanan rebuild'lerde Riverpod
    // build kapsami disindaki dinleyiciyi kendisi yeniler.
    ref.listen<UpdateState>(updateNotifierProvider, (previous, next) {
      if (previous?.isLoading == true && next.isLoading == false) {
        _presentResult(next.result);
      }
    });

    return widget.child;
  }
}