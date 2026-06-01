/// Semantic app version in the form `major.minor.patch(+build)`.
///
/// Acts as the source of truth for comparing the current version (from
/// `package_info_plus`) against the version from a release (GitHub `tag_name`
/// or `sparkle:version` in an appcast). The `+build` part is only compared when
/// `major.minor.patch` are equal.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// Parses a version string. Accepts a leading `v` (as in git tags); missing
  /// components default to zero. Returns `null` if the string cannot be parsed.
  static AppVersion? tryParse(String input) {
    var text = input.trim();

    if (text.isEmpty) {
      return null;
    }

    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }

    final buildSplit = text.split('+');

    if (buildSplit.length > 2) {
      return null;
    }

    final build = buildSplit.length == 2 ? _parseInt(buildSplit[1]) : 0;

    if (build == null) {
      return null;
    }

    final parts = buildSplit[0].split('.');

    if (parts.isEmpty || parts.length > 3) {
      return null;
    }

    final major = _parseInt(parts[0]);
    final minor = parts.length > 1 ? _parseInt(parts[1]) : 0;
    final patch = parts.length > 2 ? _parseInt(parts[2]) : 0;

    if (major == null || minor == null || patch == null) {
      return null;
    }

    return AppVersion(major, minor, patch, build);
  }

  static int? _parseInt(String value) {
    if (value.isEmpty) {
      return null;
    }

    final parsed = int.tryParse(value);

    if (parsed == null || parsed < 0) {
      return null;
    }

    return parsed;
  }

  @override
  int compareTo(AppVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) {
      return byMajor;
    }

    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) {
      return byMinor;
    }

    final byPatch = patch.compareTo(other.patch);
    if (byPatch != 0) {
      return byPatch;
    }

    return build.compareTo(other.build);
  }

  /// `true` if `other` is a newer version than this one.
  bool isOlderThan(AppVersion other) => compareTo(other) < 0;

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

    return build == 0 ? base : '$base+$build';
  }
}
