// Generates Linux desktop integration inside the built Linux bundle: icon-theme
// PNGs, a `.desktop` launcher and a per-user install/uninstall script.
//
// icons_launcher only emits snap assets, so the plain `flutter build linux`
// tarball ships no icon — a manually installed bundle then has no taskbar icon
// (on Wayland the icon is matched purely by app_id -> .desktop -> icon theme)
// and no application-menu entry. This fills that gap. Run from `mise
// build-linux` after `flutter build linux`.
//
// The square source is reused from snap/gui/knitcalc.png (256x256), which
// icons_launcher produces from the non-square assets/icon/icon.png with the
// same squaring as every other platform, keeping the Linux icon consistent.
import 'dart:io';

import 'package:image/image.dart' as img;

/// Must equal APPLICATION_ID in linux/CMakeLists.txt and the GtkApplication
/// id/prgname set in linux/runner/my_application.cc — Wayland matches the window
/// to its icon by this app_id, so the .desktop basename and StartupWMClass use
/// it verbatim.
const String appId = 'io.github.dmezhnov.knitcalc';
const String bundleDir = 'build/linux/x64/release/bundle';
const String sourceIcon = 'snap/gui/knitcalc.png';

/// Standard hicolor icon sizes; capped at the 256px source to avoid upscaling.
const List<int> iconSizes = [16, 24, 32, 48, 64, 128, 256];

void main() {
  final source = File(sourceIcon);
  if (!source.existsSync()) {
    stderr.writeln(
      'linux_desktop_install: $sourceIcon not found '
      '(run `dart run icons_launcher:create` first).',
    );
    exit(1);
  }

  if (!Directory(bundleDir).existsSync()) {
    stderr.writeln(
      'linux_desktop_install: $bundleDir not found '
      '(run `flutter build linux` first).',
    );
    exit(1);
  }

  final icon = img.decodePng(source.readAsBytesSync());
  if (icon == null) {
    stderr.writeln('linux_desktop_install: failed to decode $sourceIcon.');
    exit(1);
  }

  // Icon-theme PNGs, shipped under the bundle so install.sh can copy the whole
  // hicolor tree into the user's data dir.
  for (final size in iconSizes) {
    final resized = img.copyResize(
      icon,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    final out = File(
      '$bundleDir/desktop/icons/hicolor/${size}x$size/apps/$appId.png',
    );
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(img.encodePng(resized));
  }

  // install.sh substitutes @EXEC@ with the absolute path of the extracted
  // binary, since the tarball can be unpacked anywhere.
  File('$bundleDir/desktop/$appId.desktop').writeAsStringSync(
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=KnitCalc\n'
    'Comment=Knitting calculator\n'
    'Comment[ru]=Калькулятор для вязания\n'
    'Exec=@EXEC@\n'
    'Icon=$appId\n'
    'Terminal=false\n'
    'Categories=Utility;\n'
    'StartupWMClass=$appId\n',
  );

  File('$bundleDir/install.sh').writeAsStringSync(_installScript);
  File('$bundleDir/uninstall.sh').writeAsStringSync(_uninstallScript);
  Process.runSync('chmod', [
    '+x',
    '$bundleDir/install.sh',
    '$bundleDir/uninstall.sh',
  ]);

  stdout.writeln(
    'linux_desktop_install: wrote desktop integration into $bundleDir '
    '(${iconSizes.length} icon sizes, $appId.desktop, install.sh).',
  );
}

const String _installScript = '''
#!/bin/sh
# Installs KnitCalc desktop integration for the current user: copies the icon
# theme PNGs and a .desktop launcher into ~/.local/share so the window gets a
# taskbar icon (matched by app_id io.github.dmezhnov.knitcalc) and a menu entry.
set -e
here=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
app_id=io.github.dmezhnov.knitcalc
data=\${XDG_DATA_HOME:-\$HOME/.local/share}

cp -a "\$here/desktop/icons/hicolor/." "\$data/icons/hicolor/"

mkdir -p "\$data/applications"
sed "s|@EXEC@|\$here/knitcalc|g" "\$here/desktop/\$app_id.desktop" \\
  > "\$data/applications/\$app_id.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "\$data/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "\$data/icons/hicolor" 2>/dev/null || true
fi

echo "KnitCalc установлен для текущего пользователя."
echo "Если иконка не появилась сразу — перезапустите приложение или сеанс."
''';

const String _uninstallScript = '''
#!/bin/sh
# Removes the per-user KnitCalc desktop integration installed by install.sh.
set -e
app_id=io.github.dmezhnov.knitcalc
data=\${XDG_DATA_HOME:-\$HOME/.local/share}

rm -f "\$data/applications/\$app_id.desktop"
find "\$data/icons/hicolor" -name "\$app_id.png" -delete 2>/dev/null || true

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "\$data/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "\$data/icons/hicolor" 2>/dev/null || true
fi

echo "Десктоп-интеграция KnitCalc удалена."
''';
