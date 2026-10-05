/// Semantic version comparison utilities.
///
/// Supports standard semver format: `major.minor.patch` with optional build metadata.
/// Build metadata (after `+`) is ignored for comparison purposes.
///
/// Examples:
/// - `1.0.0 == 1.0.0` → 0
/// - `1.0.0 < 1.1.0` → -1
/// - `1.10.0 > 1.9.0` → 1
/// - `1.0.0+5 == 1.0.0+3` → 0 (build metadata ignored)
/// - `2.0.0 > 1.99.99` → 1
library version_compare;

/// Represents a parsed semantic version.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int? build; // build number from versionCode (after `+`)

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
  });

  /// Parses a version string like `1.0.0`, `1.0.0+5`, `1.10.0+5`.
  ///
  /// Returns `null` if the version string is invalid.
  static AppVersion? parse(String? version) {
    if (version == null || version.isEmpty) return null;

    try {
      // Split version and build metadata (after `+`)
      final parts = version.split('+');
      final versionPart = parts[0];
      final buildPart = parts.length > 1 ? parts[1] : null;

      final versionNumbers = versionPart.split('.');
      if (versionNumbers.length < 3) return null;

      final major = int.parse(versionNumbers[0]);
      final minor = int.parse(versionNumbers[1]);
      final patch = int.parse(versionNumbers[2]);

      final build = buildPart != null ? int.tryParse(buildPart) : null;

      return AppVersion(
        major: major,
        minor: minor,
        patch: patch,
        build: build,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Build number is only compared if both have it
    if (build != null && other.build != null) {
      return build!.compareTo(other.build!);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      build == other.build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return build != null ? '$base+$build' : base;
  }
}

/// Update check result enumeration.
enum UpdateStatus {
  /// No update needed (current >= latest)
  upToDate,

  /// Optional update available (current < latest but current >= minimum)
  optionalUpdate,

  /// Forced update required (current < minimum)
  forcedUpdate,

  /// Network/config error, status unknown
  unknown,
}

/// Result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumVersion,
    this.downloadUrl,
    this.error,
  });

  final UpdateStatus status;
  final String currentVersion;
  final String latestVersion;
  final String minimumVersion;
  final String? downloadUrl;
  final String? error;

  bool get isUpdateAvailable => status == UpdateStatus.optionalUpdate || status == UpdateStatus.forcedUpdate;
  bool get isForcedUpdate => status == UpdateStatus.forcedUpdate;

  @override
  String toString() {
    return 'UpdateCheckResult(status: $status, current: $currentVersion, latest: $latestVersion, minimum: $minimumVersion, url: $downloadUrl, error: $error)';
  }
}