// Renders every store / package-manager listing from the single source of
// truth, packaging/metadata/metadata.yaml: names, taglines, descriptions, URLs,
// tags, categories and screenshots.
//
//   dart run tool/packaging_metadata.dart            # write (mise metadata)
//   dart run tool/packaging_metadata.dart --check     # fail if anything drifted
//
// Two kinds of targets:
//   - files that are pure listing metadata (fastlane texts, winget locale
//     manifest, Scoop manifest, Chocolatey nuspec, apt control/.desktop, the
//     AppStream metainfo, the Flatpak/Snap .desktop files, the Homebrew cask)
//     are written whole from the templates below;
//   - files that also carry hand-written build logic (PKGBUILD/.SRCINFO, the
//     rpm spec, snapcraft.yaml, the F-Droid recipe, the Inno script, pubspec)
//     get only their metadata fields rewritten in place.
//
// The icon is deliberately not part of this file's input: every channel derives
// it from assets/icon/icon.png via icons_launcher + tool/packaging_icons.dart.
//
// `mise lint` runs --check, so a listing can never silently disagree with
// metadata.yaml; the release then publishes identical copy everywhere.
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const String metadataFile = 'packaging/metadata/metadata.yaml';
const String screenshotRoot = 'packaging/metadata/screenshots';

/// Rendered into every generated file that tolerates comments.
String banner(String comment) =>
    '$comment Generated from $metadataFile by tool/packaging_metadata.dart.\n'
    '$comment Edit that file and run `mise metadata`; changes here are overwritten.\n';

void main(List<String> args) {
  final check = args.contains('--check');
  final meta = Meta.load(metadataFile);

  final plan = Plan();
  _renderFastlane(meta, plan);
  _renderWinget(meta, plan);
  _renderScoop(meta, plan);
  _renderChocolatey(meta, plan);
  _renderApt(meta, plan);
  _renderDesktopEntries(meta, plan);
  _renderMetainfo(meta, plan);
  _renderHomebrew(meta, plan);
  _renderMise(meta, plan);
  _renderMisePlugin(meta, plan);
  _renderGithubRepo(meta, plan);
  _renderScreenshots(meta, plan);

  _patchSnapcraft(meta, plan);
  _patchFdroid(meta, plan);
  _patchSpec(meta, plan);
  _patchAur(meta, plan);
  _patchInno(meta, plan);
  _patchPubspec(meta, plan);

  plan.apply(check: check);
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class L10n {
  L10n({
    required this.tag,
    required this.lang,
    required this.name,
    required this.tagline,
    required this.summary,
    required this.intro,
    required this.features,
    required this.captions,
  });

  /// Locale directory name (`en-US`), as used by fastlane and the screenshots.
  final String tag;

  /// BCP-47 language used by AppStream `xml:lang` and `.desktop` key suffixes.
  final String lang;
  final String name;
  final String tagline;
  final String summary;
  final String intro;
  final List<String> features;
  final Map<String, String> captions;

  /// Long description as plain text: paragraph, blank line, bulleted features.
  String longText(String marker) =>
      '$intro\n\n${features.map((f) => '$marker $f').join('\n')}';
}

class Meta {
  Meta._({
    required this.appId,
    required this.package,
    required this.aurPackage,
    required this.wingetId,
    required this.name,
    required this.publisherName,
    required this.publisherAccount,
    required this.publisherEmail,
    required this.publisherUrl,
    required this.licenseId,
    required this.licenseUrl,
    required this.homepage,
    required this.website,
    required this.repository,
    required this.issues,
    required this.changelog,
    required this.freedesktopCategories,
    required this.fdroidCategories,
    required this.tags,
    required this.screenshots,
    required this.locales,
  });

  final String appId;
  final String package;
  final String aurPackage;
  final String wingetId;
  final String name;
  final String publisherName;
  final String publisherAccount;
  final String publisherEmail;
  final String publisherUrl;
  final String licenseId;
  final String licenseUrl;
  final String homepage;
  final String website;
  final String repository;
  final String issues;
  final String changelog;
  final List<String> freedesktopCategories;
  final List<String> fdroidCategories;
  final List<String> tags;

  /// Form factor (`desktop`, `phone`) to the ordered screenshot ids.
  final Map<String, List<String>> screenshots;

  /// Locale tag to its texts; iteration order is the file's, so the first entry
  /// is the default locale (the one single-locale channels get).
  final Map<String, L10n> locales;

  L10n get defaultLocale => locales.values.first;

  /// `Categories=` value for a `.desktop` file (trailing semicolon included).
  String get desktopCategories =>
      freedesktopCategories.map((c) => '$c;').join();

  static Meta load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      _fail('$path not found (run from the repository root).');
    }
    final root = loadYaml(file.readAsStringSync()) as YamlMap;

    final ids = root['ids'] as YamlMap;
    final publisher = root['publisher'] as YamlMap;
    final license = root['license'] as YamlMap;
    final urls = root['urls'] as YamlMap;
    final categories = root['categories'] as YamlMap;

    final screenshots = <String, List<String>>{
      for (final entry in (root['screenshots'] as YamlMap).entries)
        entry.key as String: [
          for (final shot in entry.value as YamlList) shot['id'] as String,
        ],
    };

    final locales = <String, L10n>{};
    for (final entry in (root['locales'] as YamlMap).entries) {
      final tag = entry.key as String;
      final value = entry.value as YamlMap;
      locales[tag] = L10n(
        tag: tag,
        lang: value['lang'] as String,
        name: value['name'] as String,
        tagline: value['tagline'] as String,
        summary: value['summary'] as String,
        intro: (value['intro'] as String).trim(),
        features: [for (final f in value['features'] as YamlList) f as String],
        captions: {
          for (final c in (value['captions'] as YamlMap).entries)
            c.key as String: c.value as String,
        },
      );
    }
    if (locales.isEmpty) _fail('$path: at least one locale is required.');

    final meta = Meta._(
      appId: ids['app'] as String,
      package: ids['package'] as String,
      aurPackage: ids['aur'] as String,
      wingetId: ids['winget'] as String,
      name: root['name'] as String,
      publisherName: publisher['name'] as String,
      publisherAccount: publisher['account'] as String,
      publisherEmail: publisher['email'] as String,
      publisherUrl: publisher['url'] as String,
      licenseId: license['id'] as String,
      licenseUrl: license['url'] as String,
      homepage: urls['homepage'] as String,
      website: urls['website'] as String,
      repository: urls['repository'] as String,
      issues: urls['issues'] as String,
      changelog: urls['changelog'] as String,
      freedesktopCategories: [
        for (final c in categories['freedesktop'] as YamlList) c as String,
      ],
      fdroidCategories: [
        for (final c in categories['fdroid'] as YamlList) c as String,
      ],
      tags: [for (final t in root['tags'] as YamlList) t as String],
      screenshots: screenshots,
      locales: locales,
    );
    meta._validate();
    return meta;
  }

  /// Store-side limits worth catching here rather than in a store's review
  /// queue days later.
  void _validate() {
    for (final l in locales.values) {
      // Snap: 79 chars. Play short description: 80. winget/Chocolatey: longer.
      if (l.summary.length > 79) {
        _fail(
          '${l.tag}: summary is ${l.summary.length} chars; the Snap Store '
          'caps it at 79.',
        );
      }
      // AppStream recommends <=35 and rejects a trailing period.
      if (l.tagline.length > 35) {
        _fail(
          '${l.tag}: tagline is ${l.tagline.length} chars; AppStream wants '
          'at most 35.',
        );
      }
      if (l.tagline.endsWith('.')) {
        _fail('${l.tag}: tagline must not end with a period (AppStream).');
      }
      if (l.tagline.toLowerCase().startsWith(name.toLowerCase())) {
        _fail(
          '${l.tag}: tagline must not start with the application name '
          '(AppStream and Homebrew both reject it).',
        );
      }
      // Play caps the full description at 4000 characters.
      if (l.longText('*').length > 4000) {
        _fail('${l.tag}: full description exceeds Google Play\'s 4000 chars.');
      }
      for (final ids in screenshots.values) {
        for (final id in ids) {
          if (!l.captions.containsKey(id)) {
            _fail('${l.tag}: no caption for screenshot "$id".');
          }
        }
      }
    }
    for (final form in screenshots.keys) {
      for (final id in screenshots[form]!) {
        for (final l in locales.values) {
          final path = '$screenshotRoot/${l.tag}/$form/$id.png';
          if (!File(path).existsSync()) _fail('missing screenshot $path.');
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Generated files
// ---------------------------------------------------------------------------

/// fastlane/ is read straight from this repository by IzzyOnDroid and is the
/// copy source for Play and every other Android catalogue (see
/// packaging/README.md), so it carries the texts for every locale.
void _renderFastlane(Meta meta, Plan plan) {
  for (final l in meta.locales.values) {
    final dir = 'fastlane/metadata/android/${l.tag}';
    plan.text('$dir/title.txt', '${l.name}\n');
    plan.text('$dir/short_description.txt', '${l.summary}\n');
    plan.text('$dir/full_description.txt', '${l.longText('*')}\n');
  }
}

void _renderWinget(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  plan.text(
    'packaging/winget/${meta.wingetId}.locale.${l.tag}.yaml',
    '${banner('#')}'
        '# {{VERSION}} is the bare semver (no +build), filled in by the publish\n'
        '# workflow / wingetcreate.\n'
        'PackageIdentifier: ${meta.wingetId}\n'
        "PackageVersion: '{{VERSION}}'\n"
        'PackageLocale: ${l.tag}\n'
        'Publisher: ${meta.publisherName}\n'
        'PublisherUrl: ${meta.publisherUrl}\n'
        'PublisherSupportUrl: ${meta.issues}\n'
        'PackageName: ${l.name}\n'
        'PackageUrl: ${meta.homepage}\n'
        'License: ${meta.licenseId}\n'
        'LicenseUrl: ${meta.licenseUrl}\n'
        'ShortDescription: ${_yamlScalar(l.summary)}\n'
        'Description: |-\n'
        '${_indent(l.longText('-'), '    ')}\n'
        'Tags:\n'
        '${meta.tags.map((t) => '    - $t\n').join()}'
        'ManifestType: defaultLocale\n'
        'ManifestVersion: 1.6.0\n',
  );
}

/// A Scoop manifest is JSON, which has no comments — Scoop's schema reserves
/// the `##` key for exactly that. Written as text rather than encoded from a
/// map so the layout matches what prettier (via `mise lint`) expects.
void _renderScoop(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  plan.text(
    'packaging/scoop/${meta.package}.json',
    '{\n'
        '    "##": [\n'
        '        "Generated from $metadataFile by tool/packaging_metadata.dart.",\n'
        '        "Edit that file and run `mise metadata`; changes here are overwritten."\n'
        '    ],\n'
        '    "version": "{{VERSION}}",\n'
        '    "description": ${_json(l.summary)},\n'
        '    "homepage": ${_json(meta.homepage)},\n'
        '    "license": ${_json(meta.licenseId)},\n'
        '    "url": "{{URL}}",\n'
        '    "hash": "{{SHA256}}",\n'
        '    "bin": "${meta.package}.exe",\n'
        '    "shortcuts": [["${meta.package}.exe", ${_json(l.name)}]],\n'
        '    "checkver": {\n'
        '        "url": "https://api.github.com/repos/${meta.publisherAccount}'
        '/${meta.package}/releases/latest",\n'
        '        "jsonpath": "\$.tag_name",\n'
        '        "regex": "v([\\\\d.]+\\\\+\\\\d+)"\n'
        '    },\n'
        '    "autoupdate": {\n'
        '        "url": "${meta.homepage}/releases/download/v\$version'
        '/${meta.package}-windows-x64-\$version.zip"\n'
        '    }\n'
        '}\n',
  );
}

void _renderChocolatey(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  plan.text(
    'packaging/chocolatey/${meta.package}.nuspec',
    '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated from $metadataFile by tool/packaging_metadata.dart.\n'
        '     Edit that file and run `mise metadata`; changes here are overwritten.\n'
        '     {{VERSION}} is filled in by the publish workflow (bare semver, no\n'
        '     +build: the Chocolatey gallery rejects build metadata). -->\n'
        '<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">\n'
        '  <metadata>\n'
        '    <id>${meta.package}</id>\n'
        '    <version>{{VERSION}}</version>\n'
        '    <title>${_xml(l.name)}</title>\n'
        '    <authors>${_xml(meta.publisherName)}</authors>\n'
        '    <owners>${_xml(meta.publisherAccount)}</owners>\n'
        '    <projectUrl>${meta.homepage}</projectUrl>\n'
        '    <packageSourceUrl>${meta.homepage}/tree/main/packaging/chocolatey</packageSourceUrl>\n'
        '    <projectSourceUrl>${meta.repository}</projectSourceUrl>\n'
        '    <licenseUrl>${meta.licenseUrl}</licenseUrl>\n'
        '    <requireLicenseAcceptance>false</requireLicenseAcceptance>\n'
        '    <summary>${_xml(l.summary)}</summary>\n'
        '    <description>${_xml(l.longText('-'))}</description>\n'
        '    <tags>${_xml(meta.tags.join(' '))}</tags>\n'
        '  </metadata>\n'
        '  <files>\n'
        '    <file src="tools\\**" target="tools" />\n'
        '  </files>\n'
        '</package>\n',
  );
}

/// The `Description:` field of a Debian control file: a one-line synopsis, then
/// the long description indented by one space, with ` .` for blank lines.
void _renderApt(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  final body = [
    ..._wrap(l.intro, 75).map((line) => ' $line'),
    ' .',
    ...l.features.map((f) => ' * $f'),
  ].join('\n');
  plan.text(
    'packaging/apt/control',
    'Package: ${meta.package}\n'
        'Version: {{VERSION}}\n'
        'Section: utils\n'
        'Priority: optional\n'
        'Architecture: amd64\n'
        'Depends: libgtk-3-0 (>= 3.22.0), libstdc++6\n'
        'Maintainer: ${meta.publisherName} <${meta.publisherEmail}>\n'
        'Homepage: ${meta.homepage}\n'
        'Description: ${l.summary}\n'
        '$body\n',
  );
}

/// Every `.desktop` file we ship. They differ only in `Exec`/`Icon`: the
/// canonical one keeps the `@EXEC@` placeholder that the tarball's install.sh
/// (and tool/linux_desktop_install.dart) fills in.
void _renderDesktopEntries(Meta meta, Plan plan) {
  String entry({
    required String exec,
    required String icon,
    required bool wmClass,
  }) {
    final l = meta.defaultLocale;
    final comments = [
      'Comment=${l.tagline}',
      for (final other in meta.locales.values.skip(1))
        'Comment[${other.lang}]=${other.tagline}',
    ].join('\n');
    // The banner sits inside the group, not above it: comments are legal
    // anywhere, but some naive readers expect the first line to be the header.
    return '[Desktop Entry]\n'
        '${banner('#')}'
        'Type=Application\n'
        'Name=${l.name}\n'
        '$comments\n'
        'Exec=$exec\n'
        'Icon=$icon\n'
        'Terminal=false\n'
        'Categories=${meta.desktopCategories}\n'
        '${wmClass ? 'StartupWMClass=${meta.appId}\n' : ''}';
  }

  // Canonical entry, installed into the Linux tarball and ~/.local/share by
  // tool/linux_desktop_install.dart.
  plan.text(
    'packaging/desktop/${meta.appId}.desktop',
    entry(exec: '@EXEC@', icon: meta.appId, wmClass: true),
  );
  plan.text(
    'packaging/flatpak/${meta.appId}.desktop',
    entry(exec: meta.package, icon: meta.appId, wmClass: true),
  );
  // The .deb installs the icon under the plain package name.
  plan.text(
    'packaging/apt/${meta.package}.desktop',
    entry(exec: meta.package, icon: meta.package, wmClass: false),
  );
  // A snap points Icon= at the packed file inside the snap.
  plan.text(
    'snap/gui/${meta.package}.desktop',
    entry(
      exec: meta.package,
      icon: '\${SNAP}/meta/gui/${meta.package}.png',
      wmClass: false,
    ),
  );
}

/// AppStream metainfo — read by Flathub, GNOME Software, KDE Discover and the
/// AppImage catalogue. The `<release>` entry is rewritten per release by the
/// publish workflow, so carry the existing one over verbatim.
void _renderMetainfo(Meta meta, Plan plan) {
  final path = 'packaging/flatpak/${meta.appId}.metainfo.xml';
  final l = meta.defaultLocale;
  final others = meta.locales.values.skip(1).toList();

  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>\n')
    ..write(
      '<!-- Generated from $metadataFile by tool/packaging_metadata.dart.\n',
    )
    ..write('     Edit that file and run `mise metadata`; changes here are\n')
    ..write(
      '     overwritten — except <releases>, which the publish workflow\n',
    )
    ..write('     rewrites with the version being released. -->\n')
    ..write('<component type="desktop-application">\n')
    ..write('  <id>${meta.appId}</id>\n')
    ..write('  <name>${_xml(l.name)}</name>\n')
    ..write('  <summary>${_xml(l.tagline)}</summary>\n');
  for (final other in others) {
    buffer.write(
      '  <summary xml:lang="${other.lang}">${_xml(other.tagline)}</summary>\n',
    );
  }
  buffer
    ..write('  <metadata_license>${meta.licenseId}</metadata_license>\n')
    ..write('  <project_license>${meta.licenseId}</project_license>\n')
    ..write('  <developer id="${_developerId(meta.appId)}">\n')
    ..write('    <name>${_xml(meta.publisherName)}</name>\n')
    ..write('  </developer>\n')
    ..write(
      '  <launchable type="desktop-id">${meta.appId}.desktop</launchable>\n',
    )
    ..write('  <provides>\n')
    ..write('    <binary>${meta.package}</binary>\n')
    ..write('  </provides>\n')
    ..write('  <description>\n')
    ..write(_xmlParagraph(l.intro, '    '));
  for (final other in others) {
    buffer.write(_xmlParagraph(other.intro, '    ', lang: other.lang));
  }
  buffer.write('    <ul>\n');
  for (var i = 0; i < l.features.length; i++) {
    buffer.write('      <li>${_xml(l.features[i])}</li>\n');
    for (final other in others) {
      buffer.write(
        '      <li xml:lang="${other.lang}">${_xml(other.features[i])}</li>\n',
      );
    }
  }
  buffer
    ..write('    </ul>\n')
    ..write('  </description>\n')
    ..write('  <screenshots>\n');
  final desktopShots = meta.screenshots['desktop'] ?? const [];
  for (var i = 0; i < desktopShots.length; i++) {
    final id = desktopShots[i];
    buffer
      ..write('    <screenshot${i == 0 ? ' type="default"' : ''}>\n')
      ..write('      <image>${_shotUrl(meta, l.tag, 'desktop', id)}</image>\n');
    for (final other in others) {
      buffer.write(
        '      <image xml:lang="${other.lang}">'
        '${_shotUrl(meta, other.tag, 'desktop', id)}</image>\n',
      );
    }
    buffer.write('      <caption>${_xml(l.captions[id]!)}</caption>\n');
    for (final other in others) {
      buffer.write(
        '      <caption xml:lang="${other.lang}">'
        '${_xml(other.captions[id]!)}</caption>\n',
      );
    }
    buffer.write('    </screenshot>\n');
  }
  buffer
    ..write('  </screenshots>\n')
    ..write('  <url type="homepage">${meta.homepage}</url>\n')
    ..write('  <url type="bugtracker">${meta.issues}</url>\n')
    ..write('  <url type="vcs-browser">${meta.repository}</url>\n')
    ..write('  <content_rating type="oars-1.1"/>\n')
    ..write('  <releases>\n')
    ..write(_existingReleases(path))
    ..write('  </releases>\n')
    ..write('</component>\n');

  plan.text(path, buffer.toString());
}

/// `io.github.dmezhnov.knitcalc` -> `io.github.dmezhnov`, the AppStream
/// developer id convention for a GitHub-hosted project.
String _developerId(String appId) {
  final parts = appId.split('.');
  return parts.sublist(0, parts.length - 1).join('.');
}

String _shotUrl(Meta meta, String locale, String form, String id) =>
    'https://raw.githubusercontent.com/${meta.publisherAccount}/'
    '${meta.package}/main/$screenshotRoot/$locale/$form/$id.png';

/// Keeps the `<release …/>` line(s) already in the metainfo (the publish
/// workflow owns them). Falls back to the pubspec version for a fresh file.
String _existingReleases(String path) {
  final file = File(path);
  if (file.existsSync()) {
    final lines = RegExp(r'^\s*<release .*$', multiLine: true)
        .allMatches(file.readAsStringSync())
        .map((m) => '    ${m.group(0)!.trim()}\n')
        .join();
    if (lines.isNotEmpty) return lines;
  }
  final version = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  final today = DateTime.now().toUtc().toIso8601String().split('T').first;
  return '    <release version="$version" date="$today"/>\n';
}

void _renderHomebrew(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  plan.text(
    'packaging/homebrew/${meta.package}.rb',
    '${banner('#')}'
        '#\n'
        '# Homebrew cask template. {{VERSION}}, {{URL}} and {{SHA256}} are filled in\n'
        '# by the `publish` job of .github/workflows/publish.yml, which renders the\n'
        '# result to Casks/${meta.package}.rb on main — the repo itself doubles as the\n'
        '# tap, exactly like the Scoop bucket. Version keeps the full +build metadata\n'
        '# (the macOS zip filename and release URL do too); cask versions are free-form.\n'
        'cask "${meta.package}" do\n'
        '  version "{{VERSION}}"\n'
        '  sha256 "{{SHA256}}"\n'
        '\n'
        '  url "{{URL}}",\n'
        '      verified: "github.com/${meta.publisherAccount}/${meta.package}/"\n'
        '  name "${l.name}"\n'
        '  desc "${l.summary}"\n'
        '  homepage "${meta.homepage}"\n'
        '\n'
        '  app "${meta.package}.app"\n'
        '\n'
        '  # The macOS build is unsigned and unnotarized, so install with\n'
        '  # `--no-quarantine` (otherwise Gatekeeper blocks first launch).\n'
        '  zap trash: [\n'
        '    "~/Library/Application Support/${meta.appId}",\n'
        '    "~/Library/Preferences/${meta.appId}.plist",\n'
        '    "~/Library/Saved Application State/${meta.appId}.savedState",\n'
        '  ]\n'
        'end\n',
  );
}

/// Registry entry for the mise version manager, ready to be copied into
/// `registry/${meta.package}.toml` of a jdx/mise fork (see packaging/README.md).
///
/// Unlike every other channel there is nothing to publish per release: mise
/// installs the GitHub release assets directly, so the entry carries no version
/// and the release workflow only verifies that the install still works. The
/// per-platform asset globs are deliberate — a release also carries the
/// AppImage, the Android APKs, the web tarball, the iOS zip and the Inno
/// setup.exe, and mise's autodetection could pick any of them.
void _renderMise(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  final bundle = '${meta.package}.app/Contents/MacOS';
  plan.text(
    'packaging/mise/${meta.package}.toml',
    '${banner('#')}'
        '#\n'
        '# Copy to registry/${meta.package}.toml in a fork of jdx/mise; users then\n'
        '# install with `mise use -g ${meta.package}`. Until that PR lands, the\n'
        '# install instructions in packaging/README.md spell the same backend and\n'
        '# options out in the user\'s own mise config.\n'
        'description = ${_json(l.summary)}\n'
        'version_order = "semver"\n'
        '\n'
        'bins = ["${meta.package}"]\n'
        'test = { cmd = "${meta.package} --version", '
        'expected = "${meta.package} {{version}}" }\n'
        '\n'
        '[[backends]]\n'
        'full = "github:${meta.publisherAccount}/${meta.package}"\n'
        '\n'
        '[backends.options.platforms.linux-x64]\n'
        'asset_pattern = "${meta.package}-linux-x64-*.tar.gz"\n'
        '\n'
        '[backends.options.platforms.windows-x64]\n'
        'asset_pattern = "${meta.package}-windows-x64-*.zip"\n'
        '\n'
        '# The macOS asset is an .app bundle, so the binary sits inside it.\n'
        '[backends.options.platforms.macos-arm64]\n'
        'asset_pattern = "${meta.package}-macos-*.zip"\n'
        'bin_path = "$bundle"\n'
        '\n'
        '[backends.options.platforms.macos-x64]\n'
        'asset_pattern = "${meta.package}-macos-*.zip"\n'
        'bin_path = "$bundle"\n',
  );
}

/// The mise **tool plugin** that makes this repository its own tool registry:
/// `mise plugin install knitcalc <repo url>` then `mise use -g knitcalc`, no
/// entry in jdx/mise needed. Only these two files are generated — the hooks
/// next to them are code and stay hand-written; everything of theirs that could
/// drift from this file (repository, package name, the app's display name)
/// lives in `lib/knitcalc.lua`.
///
/// The publish job copies the rendered tree to the root of `main`, where mise
/// expects a plugin's `metadata.lua`/`hooks/`, exactly as it does for the Scoop
/// bucket and the Homebrew cask. The shared module therefore sits at the plugin
/// root rather than in the documented `lib/` — `lib/` at the root of *this*
/// repository is the Flutter source tree; mise resolves `require` from the
/// plugin root just as well (verified).
void _renderMisePlugin(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  const root = 'packaging/mise/plugin';

  plan.text(
    '$root/metadata.lua',
    '${banner('--')}'
        'PLUGIN = {\n'
        '    name = "${meta.package}",\n'
        '    version = "1.0.0",\n'
        '    description = ${_json(l.summary)},\n'
        '    author = ${_json(meta.publisherName)},\n'
        '}\n',
  );

  plan.text(
    '$root/${meta.package}.lua',
    '${banner('--')}'
        'local M = {}\n'
        '\n'
        'M.repo = "${meta.publisherAccount}/${meta.package}"\n'
        'M.package = "${meta.package}"\n'
        '-- User-visible name, used by the hooks that add the app to the\n'
        '-- Windows Start menu and to ~/Applications on macOS.\n'
        'M.displayName = ${_json(l.name)}\n'
        'M.apiHeaders = {\n'
        '    Accept = "application/vnd.github+json",\n'
        '    ["User-Agent"] = "mise-${meta.package}-plugin",\n'
        '    ["X-GitHub-Api-Version"] = "2022-11-28",\n'
        '}\n'
        '\n'
        '-- Release tags are the pubspec version with a "v" prefix ("v1.2.3+45").\n'
        'function M.versionFromTag(tag)\n'
        '    return (string.gsub(tag, "^v", ""))\n'
        'end\n'
        '\n'
        '-- Desktop bundles published per platform. Linux and Windows ship x64\n'
        '-- only; the macOS zip is a universal .app bundle, so both arches take it.\n'
        'function M.assetName(version)\n'
        '    local os_type = RUNTIME.osType\n'
        '    local arch = RUNTIME.archType\n'
        '\n'
        '    if os_type == "linux" and arch == "amd64" then\n'
        '        return "${meta.package}-linux-x64-" .. version .. ".tar.gz"\n'
        '    elseif os_type == "windows" and arch == "amd64" then\n'
        '        return "${meta.package}-windows-x64-" .. version .. ".zip"\n'
        '    elseif os_type == "darwin" then\n'
        '        return "${meta.package}-macos-" .. version .. ".zip"\n'
        '    end\n'
        '\n'
        '    error("${meta.package}: no release build for " '
        '.. tostring(os_type) .. "-" .. tostring(arch))\n'
        'end\n'
        '\n'
        'return M\n',
  );
}

/// The GitHub repository page is a listing like any other: its description,
/// website and topics are pushed by packaging/ci/publish_repo_metadata.sh on
/// every release. That step runs on a bare runner with no Dart, so the values
/// are handed over as JSON for `jq` rather than re-parsed from the YAML.
void _renderGithubRepo(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  plan.text(
    'packaging/metadata/github.json',
    '{\n'
        '    "##": [\n'
        '        "Generated from $metadataFile by tool/packaging_metadata.dart.",\n'
        '        "Edit that file and run `mise metadata`; changes here are overwritten.",\n'
        '        "Pushed to the repository by packaging/ci/publish_repo_metadata.sh."\n'
        '    ],\n'
        '    "description": ${_json(l.summary)},\n'
        '    "homepage": ${_json(meta.website)},\n'
        '    "topics": [${meta.tags.map(_json).join(', ')}]\n'
        '}\n',
  );
}

/// fastlane wants the phone screenshots as numbered files in its own tree;
/// copy them from the canonical set so both stay one edit apart.
void _renderScreenshots(Meta meta, Plan plan) {
  final phone = meta.screenshots['phone'] ?? const [];
  for (final l in meta.locales.values) {
    final dir = 'fastlane/metadata/android/${l.tag}/images/phoneScreenshots';
    for (var i = 0; i < phone.length; i++) {
      plan.copy(
        '$screenshotRoot/${l.tag}/phone/${phone[i]}.png',
        '$dir/${i + 1}.png',
      );
    }
    plan.prune(dir, {for (var i = 0; i < phone.length; i++) '${i + 1}.png'});
  }
}

// ---------------------------------------------------------------------------
// Files patched in place (they also carry build logic)
// ---------------------------------------------------------------------------

void _patchSnapcraft(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  final header =
      'name: ${meta.package}\n'
      'title: ${l.name}\n'
      "version: '{{VERSION}}'\n"
      'summary: ${_yamlScalar(l.summary)}\n'
      'description: |\n'
      '${_indent(l.longText('-'), '    ')}\n'
      'license: ${meta.licenseId}\n'
      'website: ${meta.website}\n'
      'source-code: ${meta.repository}\n'
      'issues: ${meta.issues}';
  plan.patch('snap/snapcraft.yaml', (content) {
    return _replaceBlock(
      content,
      'snap/snapcraft.yaml',
      start: RegExp(r'^name: ', multiLine: true),
      end: RegExp(r'^issues: .*$', multiLine: true),
      replacement: header,
    );
  });
}

void _patchFdroid(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  final block =
      'Categories:\n'
      '${meta.fdroidCategories.map((c) => '    - $c\n').join()}'
      'License: ${meta.licenseId}\n'
      'AuthorName: ${meta.publisherName}\n'
      'AuthorEmail: ${meta.publisherEmail}\n'
      'WebSite: ${meta.website}\n'
      'SourceCode: ${meta.repository}\n'
      'IssueTracker: ${meta.issues}\n'
      'Changelog: ${meta.changelog}\n'
      '\n'
      'AutoName: ${l.name}\n'
      'Summary: ${_yamlScalar(l.summary)}\n'
      'Description: |-\n'
      '${_indent(l.longText('*'), '    ')}';
  plan.patch('packaging/fdroid/${meta.appId}.yml', (content) {
    return _replaceRegion(
      content,
      'packaging/fdroid/${meta.appId}.yml',
      start: RegExp(r'^Categories:$', multiLine: true),
      // Everything up to the build recipe is listing metadata; anchoring on the
      // recipe (rather than on the block's own last key) keeps the replacement
      // idempotent when fields are added or removed.
      endBefore: RegExp(r'^RepoType:', multiLine: true),
      replacement: '$block\n\n',
    );
  });
}

void _patchSpec(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  const path = 'packaging/obs/knitcalc.spec';
  plan.patch(path, (content) {
    var out = _replaceLine(
      content,
      path,
      RegExp(r'^Name:.*$', multiLine: true),
      'Name:           ${meta.package}',
    );
    out = _replaceLine(
      out,
      path,
      // Summary must be short and unpunctuated for rpmlint.
      RegExp(r'^Summary:.*$', multiLine: true),
      'Summary:        ${l.tagline}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^License:.*$', multiLine: true),
      'License:        ${meta.licenseId}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^URL:.*$', multiLine: true),
      'URL:            ${meta.homepage}',
    );
    final description = [
      ..._wrap(l.intro, 75),
      '',
      ...l.features.map((f) => '* $f'),
    ].join('\n');
    return _replaceLine(
      out,
      path,
      RegExp(r'^%description\n[\s\S]*?(?=^%prep$)', multiLine: true),
      '%description\n$description\n\n',
    );
  });
}

void _patchAur(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  const pkgbuild = 'packaging/aur/PKGBUILD';
  plan.patch(pkgbuild, (content) {
    var out = _replaceLine(
      content,
      pkgbuild,
      RegExp(r'^pkgname=.*$', multiLine: true),
      'pkgname=${meta.aurPackage}',
    );
    out = _replaceLine(
      out,
      pkgbuild,
      RegExp(r'^pkgdesc=.*$', multiLine: true),
      'pkgdesc="${l.summary}"',
    );
    out = _replaceLine(
      out,
      pkgbuild,
      RegExp(r'^url=.*$', multiLine: true),
      'url="${meta.homepage}"',
    );
    return _replaceLine(
      out,
      pkgbuild,
      RegExp(r'^license=.*$', multiLine: true),
      "license=('${meta.licenseId}')",
    );
  });

  const srcinfo = 'packaging/aur/SRCINFO';
  plan.patch(srcinfo, (content) {
    var out = _replaceLine(
      content,
      srcinfo,
      RegExp(r'^pkgbase = .*$', multiLine: true),
      'pkgbase = ${meta.aurPackage}',
    );
    out = _replaceLine(
      out,
      srcinfo,
      RegExp(r'^\tpkgdesc = .*$', multiLine: true),
      '\tpkgdesc = ${l.summary}',
    );
    out = _replaceLine(
      out,
      srcinfo,
      RegExp(r'^\turl = .*$', multiLine: true),
      '\turl = ${meta.homepage}',
    );
    out = _replaceLine(
      out,
      srcinfo,
      RegExp(r'^\tlicense = .*$', multiLine: true),
      '\tlicense = ${meta.licenseId}',
    );
    return _replaceLine(
      out,
      srcinfo,
      RegExp(r'^pkgname = .*$', multiLine: true),
      'pkgname = ${meta.aurPackage}',
    );
  });
}

/// Only the [Setup] keys Windows shows in Add/Remove Programs; the prose in the
/// installer's own messages stays hand-written.
void _patchInno(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  const path = 'packaging/inno/knitcalc.iss';
  plan.patch(path, (content) {
    var out = _replaceLine(
      content,
      path,
      RegExp(r'^AppName=.*$', multiLine: true),
      'AppName=${l.name}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^AppVerName=.*$', multiLine: true),
      'AppVerName=${l.name} {#AppNumeric}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^AppPublisher=.*$', multiLine: true),
      'AppPublisher=${meta.publisherAccount}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^AppPublisherURL=.*$', multiLine: true),
      'AppPublisherURL=${meta.homepage}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^AppSupportURL=.*$', multiLine: true),
      'AppSupportURL=${meta.issues}',
    );
    return _replaceLine(
      out,
      path,
      RegExp(r'^UninstallDisplayName=.*$', multiLine: true),
      'UninstallDisplayName=${l.name}',
    );
  });
}

/// pub metadata is the description Dart tooling and the repo's own README
/// generator show; keep it on the same sentence as the stores.
void _patchPubspec(Meta meta, Plan plan) {
  final l = meta.defaultLocale;
  const path = 'pubspec.yaml';
  plan.patch(path, (content) {
    var out = _replaceLine(
      content,
      path,
      RegExp(r'^description:.*$', multiLine: true),
      'description: ${_yamlScalar(l.summary)}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^homepage:.*$', multiLine: true),
      'homepage: ${_yamlScalar(meta.website)}',
    );
    out = _replaceLine(
      out,
      path,
      RegExp(r'^repository:.*$', multiLine: true),
      'repository: ${_yamlScalar(meta.repository)}',
    );
    return _replaceLine(
      out,
      path,
      RegExp(r'^issue_tracker:.*$', multiLine: true),
      'issue_tracker: ${_yamlScalar(meta.issues)}',
    );
  });
}

// ---------------------------------------------------------------------------
// Plan: collect every intended change, then write it or report the drift
// ---------------------------------------------------------------------------

class Plan {
  final Map<String, String> _texts = {};
  final Map<String, String> _copies = {};
  final Map<String, Set<String>> _prunes = {};

  /// [content] replaces [path] wholesale.
  void text(String path, String content) => _texts[path] = content;

  /// [transform] rewrites the metadata fields of an existing [path].
  void patch(String path, String Function(String) transform) {
    final file = File(path);
    if (!file.existsSync()) _fail('$path not found.');
    _texts[path] = transform(file.readAsStringSync());
  }

  void copy(String from, String to) => _copies[to] = from;

  /// Files in [dir] outside [keep] are stale output and get removed.
  void prune(String dir, Set<String> keep) => _prunes[dir] = keep;

  void apply({required bool check}) {
    final stale = <String>[];

    for (final entry in _texts.entries) {
      final file = File(entry.key);
      final current = file.existsSync() ? file.readAsStringSync() : null;
      if (current == entry.value) continue;
      stale.add(entry.key);
      if (!check) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
    }

    for (final entry in _copies.entries) {
      final source = File(entry.value);
      final target = File(entry.key);
      final bytes = source.readAsBytesSync();
      if (target.existsSync() && _sameBytes(target.readAsBytesSync(), bytes)) {
        continue;
      }
      stale.add(entry.key);
      if (!check) {
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(bytes);
      }
    }

    for (final entry in _prunes.entries) {
      final dir = Directory(entry.key);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (entry.value.contains(name)) continue;
        stale.add('${entry.key}/$name (stale)');
        if (!check) file.deleteSync();
      }
    }

    if (check) {
      if (stale.isEmpty) {
        stdout.writeln(
          'packaging_metadata: every listing matches $metadataFile.',
        );
        return;
      }
      stderr.writeln(
        'packaging_metadata: these listings no longer match $metadataFile:',
      );
      for (final path in stale) {
        stderr.writeln('  $path');
      }
      stderr.writeln('Run `mise metadata` to regenerate them.');
      exit(1);
    }

    if (stale.isEmpty) {
      stdout.writeln('packaging_metadata: listings already up to date.');
      return;
    }
    stdout.writeln('packaging_metadata: updated ${stale.length} file(s):');
    for (final path in stale) {
      stdout.writeln('  $path');
    }
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Small text helpers
// ---------------------------------------------------------------------------

String _replaceLine(
  String content,
  String path,
  RegExp pattern,
  String replacement,
) {
  final matches = pattern.allMatches(content).length;
  if (matches != 1) {
    _fail(
      '$path: expected exactly one match for /${pattern.pattern}/, found '
      '$matches. The file drifted from what tool/packaging_metadata.dart '
      'knows how to patch.',
    );
  }
  return content.replaceFirst(pattern, replacement);
}

/// Replaces everything from the line matching [start] to the line matching
/// [end] (both inclusive) with [replacement].
String _replaceBlock(
  String content,
  String path, {
  required RegExp start,
  required RegExp end,
  required String replacement,
}) {
  final from = start.firstMatch(content);
  final to = end.firstMatch(content);
  if (from == null || to == null || to.end <= from.start) {
    _fail(
      '$path: could not locate the metadata block '
      '(/${start.pattern}/ … /${end.pattern}/).',
    );
  }
  return content.replaceRange(from.start, to.end, replacement);
}

/// Replaces everything from the line matching [start] up to (not including) the
/// line matching [endBefore] with [replacement].
String _replaceRegion(
  String content,
  String path, {
  required RegExp start,
  required RegExp endBefore,
  required String replacement,
}) {
  final from = start.firstMatch(content);
  final to = endBefore.firstMatch(content);
  if (from == null || to == null || to.start <= from.start) {
    _fail(
      '$path: could not locate the metadata region '
      '(/${start.pattern}/ … /${endBefore.pattern}/).',
    );
  }
  return content.replaceRange(from.start, to.start, replacement);
}

/// Greedy wrap; the inputs are single paragraphs of prose.
List<String> _wrap(String text, int width) {
  final lines = <String>[];
  var line = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (line.isEmpty) {
      line = word;
    } else if (line.length + 1 + word.length <= width) {
      line = '$line $word';
    } else {
      lines.add(line);
      line = word;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

String _indent(String text, String prefix) => text
    .split('\n')
    .map((line) => line.isEmpty ? '' : '$prefix$line')
    .join('\n');

/// Wraps [text] into an AppStream `<p>` block indented by [indent].
String _xmlParagraph(String text, String indent, {String? lang}) {
  final open = lang == null ? '<p>' : '<p xml:lang="$lang">';
  final body = _wrap(
    _xml(text),
    72 - indent.length,
  ).map((line) => '$indent  $line\n').join();
  return '$indent$open\n$body$indent</p>\n';
}

String _json(String value) => jsonEncode(value);

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Quotes a YAML scalar only when it needs it (a colon-space, a leading
/// indicator character), matching how prettier would leave it.
String _yamlScalar(String value) {
  final needsQuotes =
      value.contains(': ') ||
      value.endsWith(':') ||
      value.contains(' #') ||
      RegExp(r'''^[\s\-?:,\[\]{}#&*!|>'"%@`]''').hasMatch(value);
  if (!needsQuotes) return value;
  return "'${value.replaceAll("'", "''")}'";
}

Never _fail(String message) {
  stderr.writeln('packaging_metadata: $message');
  exit(1);
}
