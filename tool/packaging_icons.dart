// Regenerates the catalog icons that live in the repo itself (not in build
// output) from assets/icon/icon.png, so replacing the source icon updates
// every distribution channel on the next `mise build`:
//   - fastlane/metadata/android/<locale>/images/icon.png (512px) — read by
//     IzzyOnDroid / F-Droid-style catalogs straight from the repo;
//   - packaging/flatpak/io.github.dmezhnov.knitcalc.png (256px) — installed
//     from the source tree by the Flathub manifest.
//
// The squaring (center-crop, then resize) matches what icons_launcher does to
// the same source, keeping these icons consistent with every other platform.
// Run from the `mise build` task, right after icons_launcher:create.
import 'dart:io';

import 'package:image/image.dart' as img;

const String sourceIcon = 'assets/icon/icon.png';
const String fastlaneRoot = 'fastlane/metadata/android';
const String flatpakIcon = 'packaging/flatpak/io.github.dmezhnov.knitcalc.png';

void main() {
  final source = File(sourceIcon);
  if (!source.existsSync()) {
    stderr.writeln('packaging_icons: $sourceIcon not found.');
    exit(1);
  }

  final icon = img.decodePng(source.readAsBytesSync());
  if (icon == null) {
    stderr.writeln('packaging_icons: failed to decode $sourceIcon.');
    exit(1);
  }

  final side = icon.width < icon.height ? icon.width : icon.height;
  final squared = img.copyCrop(
    icon,
    x: (icon.width - side) ~/ 2,
    y: (icon.height - side) ~/ 2,
    width: side,
    height: side,
  );

  final targets = <String, int>{
    // Every locale present in the fastlane metadata gets the same icon.
    for (final locale in Directory(
      fastlaneRoot,
    ).listSync().whereType<Directory>())
      '${locale.path}/images/icon.png': 512,
    flatpakIcon: 256,
  };

  targets.forEach((path, size) {
    final resized = img.copyResize(
      squared,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    final out = File(path);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(img.encodePng(resized));
  });

  stdout.writeln(
    'packaging_icons: regenerated ${targets.length} catalog icons '
    'from $sourceIcon.',
  );
}
