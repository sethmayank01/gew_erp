class AppUpdate {
  final String version;
  final Uri? downloadUri;
  final String changelog;

  const AppUpdate(this.version, this.downloadUri, this.changelog);

  static List<int> _versionParts(String version) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$',
    ).firstMatch(version.trim());
    if (match == null) throw const FormatException('Invalid app version');
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  bool isNewerThan(String installed) {
    final latest = _versionParts(version);
    final current = _versionParts(installed);
    for (var i = 0; i < 3; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return false;
  }

  factory AppUpdate.fromManifest(
    Map<String, dynamic> manifest,
    String platform,
  ) {
    final release = manifest[platform];
    if (release is! Map)
      throw const FormatException('Missing platform release');
    final version = release['version']?.toString().trim() ?? '';
    _versionParts(version);
    final url = release[platform == 'android' ? 'apk_url' : 'installer_url']
        ?.toString();
    final uri = url == null ? null : Uri.tryParse(url);
    final validUri =
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty;
    return AppUpdate(
      version,
      validUri ? uri : null,
      manifest['changelog']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson(String platform) => {
    platform: {
      'version': version,
      platform == 'android' ? 'apk_url' : 'installer_url': downloadUri
          ?.toString(),
    },
    'changelog': changelog,
  };
}
