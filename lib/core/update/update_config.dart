/// App update configuration model.
///
/// Represents the remote configuration for app updates.
class UpdateConfig {
  const UpdateConfig({
    required this.latestVersion,
    required this.minimumVersion,
    required this.downloadUrl,
  });

  final String latestVersion;
  final String minimumVersion;
  final String downloadUrl;

  factory UpdateConfig.fromJson(Map<String, dynamic> json) {
    return UpdateConfig(
      latestVersion: json['latest_version'] as String? ?? '1.0.0',
      minimumVersion: json['minimum_version'] as String? ?? '1.0.0',
      downloadUrl: json['download_url'] as String? ?? 'https://kyronapp.pages.dev/',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latest_version': latestVersion,
      'minimum_version': minimumVersion,
      'download_url': downloadUrl,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is UpdateConfig &&
      latestVersion == other.latestVersion &&
      minimumVersion == other.minimumVersion &&
      downloadUrl == other.downloadUrl;

  @override
  int get hashCode => Object.hash(latestVersion, minimumVersion, downloadUrl);

  @override
  String toString() =>
      'UpdateConfig(latest: $latestVersion, minimum: $minimumVersion, url: $downloadUrl)';
}