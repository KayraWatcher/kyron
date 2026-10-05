/// App update check service.
///
/// Checks the current app version against the remote configuration
/// and determines the update status (up-to-date, optional, forced).
library update_service;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'version_compare.dart';
import 'update_config.dart';
import 'update_config_provider.dart';

/// Service that performs update checks.
class UpdateService {
  UpdateService({
    required this.packageInfo,
  });

  final PackageInfo? packageInfo;

  /// Checks for updates and returns the update status.
  Future<UpdateCheckResult> checkForUpdates(Ref ref) async {
    // Get current app version
    debugPrint('[UpdateService] getting current package version');
    final currentVersion = await _getCurrentVersion();
    if (currentVersion == null) {
      return UpdateCheckResult(
        status: UpdateStatus.unknown,
        currentVersion: 'unknown',
        latestVersion: 'unknown',
        minimumVersion: 'unknown',
        error: 'Could not determine current version',
      );
    }

    // Fetch remote config
    final config = await _fetchConfig(ref);
    if (config == null) {
      return UpdateCheckResult(
        status: UpdateStatus.unknown,
        currentVersion: currentVersion.toString(),
        latestVersion: 'unknown',
        minimumVersion: 'unknown',
        error: 'Failed to fetch update config',
      );
    }

    // Compare versions
    final current = AppVersion.parse(currentVersion.toString());
    final latest = AppVersion.parse(config.latestVersion);
    final minimum = AppVersion.parse(config.minimumVersion);

    if (current == null || latest == null || minimum == null) {
      return UpdateCheckResult(
        status: UpdateStatus.unknown,
        currentVersion: currentVersion.toString(),
        latestVersion: config.latestVersion,
        minimumVersion: config.minimumVersion,
        error: 'Invalid version format',
      );
    }

    // Determine update status
    UpdateStatus status;
    if (current.compareTo(latest) >= 0) {
      status = UpdateStatus.upToDate;
    } else if (current.compareTo(minimum) >= 0) {
      status = UpdateStatus.optionalUpdate;
    } else {
      status = UpdateStatus.forcedUpdate;
    }

    // TEŞHİS: Başarı yolundaki tek log. UpdateChecker'ın hangi dala girdigini
    // cihazda logcat'ten okunabilir hale getirir.
    debugPrint(
      '[UpdateService] status=${status.name} '
      'latest=${latest.toString()} '
      'minimum=${minimum.toString()} '
      'current=${current.toString()}',
    );

    return UpdateCheckResult(
      status: status,
      currentVersion: current.toString(),
      latestVersion: latest.toString(),
      minimumVersion: minimum.toString(),
      downloadUrl: config.downloadUrl,
    );
  }

  /// Gets the current app version from package_info.
  Future<String?> _getCurrentVersion() async {
    try {
      final info = packageInfo ?? await PackageInfo.fromPlatform();
      final version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
      debugPrint('[UpdateService] current package version=$version');
      return version;
    } catch (e, st) {
      // TEŞHİS: Bu sessiz catch, update zincirinin EN ÖNDEKI kırılma noktası.
      // Buraya girerse PackageInfo plugin'i release'de calismiyor demektir ve
      // checkForUpdates config fetch'e hic gelmeden 'unknown' ile doner.
      debugPrint(
        '[UpdateService] PackageInfo.fromPlatform() BASARISIZ oldu; '
        'currentVersion=null donecek, sonuc "unknown" olacak. '
        'Detay: $e\n$st',
      );
      return null;
    }
  }

  /// Fetches the update config from the remote provider.
  ///
  /// Hata durumunda `null` doner ve `checkForUpdates` sonucu `unknown` olur;
  /// production UI davranisi degismez. Ancak neden `null` dondugu loglanir,
  /// aksi halde "forced update hic cikmiyor" hatasi sessizce yutuluyordu.
  Future<UpdateConfig?> _fetchConfig(Ref ref) async {
    try {
      return await ref.read(updateConfigProvider.future);
    } catch (e) {
      debugPrint(
        '[UpdateService] update config alinamadi; sonuc "unknown" olacak. '
        'En olasi neden: SUPABASE_URL/SUPABASE_ANON_KEY build komutuna '
        '--dart-define olarak gecirilmemis ya da ag hatasi. Detay: $e',
      );
      return null;
    }
  }
}

/// Provider for the update service.
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(packageInfo: null);
});