import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/channel.dart';

void main() {
  group('androidChannelForInstaller', () {
    test('maps Google Play to androidPlay', () {
      expect(
        androidChannelForInstaller('com.android.vending'),
        Channel.androidPlay,
      );
    });

    test('maps RuStore to androidRustore', () {
      expect(androidChannelForInstaller('ru.vk.store'), Channel.androidRustore);
    });

    test('maps each managed store to its own per-store channel', () {
      const expected = {
        'com.sec.android.app.samsungapps': Channel.androidSamsung,
        'com.amazon.venezia': Channel.androidAmazon,
        'com.huawei.appmarket': Channel.androidHuawei,
        'org.fdroid.fdroid': Channel.androidFdroid,
        'app.accrescent.client': Channel.androidAccrescent,
      };

      expected.forEach((installer, channel) {
        expect(
          androidChannelForInstaller(installer),
          channel,
          reason: installer,
        );
      });
    });

    test('treats an unknown installer as a sideload', () {
      expect(
        androidChannelForInstaller('com.android.shell'),
        Channel.androidSideload,
      );
    });

    test('treats a null installer as a sideload', () {
      expect(androidChannelForInstaller(null), Channel.androidSideload);
    });
  });

  group('windowsChannelForExecutable', () {
    test('maps a scoop\\apps path to windowsScoop', () {
      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\scoop\apps\knitcalc\current\knitcalc.exe',
        ),
        Channel.windowsScoop,
      );
      // Global installs live under ProgramData but keep the scoop\apps shape.
      expect(
        windowsChannelForExecutable(
          r'C:\ProgramData\scoop\apps\knitcalc\1.8.8\knitcalc.exe',
        ),
        Channel.windowsScoop,
      );
    });

    test('is case-insensitive and tolerates forward slashes', () {
      expect(
        windowsChannelForExecutable(
          'C:/Users/me/Scoop/Apps/knitcalc/current/knitcalc.exe',
        ),
        Channel.windowsScoop,
      );
    });

    test('maps a chocolatey\\lib path to windowsChocolatey', () {
      expect(
        windowsChannelForExecutable(
          r'C:\ProgramData\chocolatey\lib\knitcalc\tools\knitcalc.exe',
        ),
        Channel.windowsChocolatey,
      );
    });

    test('maps an installer install with a winget marker to windowsWinget', () {
      // winget runs the same Inno installer; the install-source marker next to
      // the exe is what tells it apart from a direct install.
      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\AppData\Local\Programs\KnitCalc\knitcalc.exe',
          readInstallSource: (_) => 'winget',
        ),
        Channel.windowsWinget,
      );
    });

    test('maps a "manual" marker to windowsManual', () {
      // A direct (interactive) installer install writes "manual".
      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\AppData\Local\Programs\KnitCalc\knitcalc.exe',
          readInstallSource: (_) => 'manual',
        ),
        Channel.windowsManual,
      );
    });

    test('maps an unmarked copy to windowsPortable', () {
      // No marker means the Inno installer never ran here: it is a loose-zip
      // portable copy (or a rare pre-marker install) that swaps its own files
      // rather than running the installer (which would drop a second copy).
      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\Downloads\knitcalc\knitcalc.exe',
          readInstallSource: (_) => null,
        ),
        Channel.windowsPortable,
      );
      // An unexpected marker value is treated the same (defensive default).
      expect(
        windowsChannelForExecutable(
          r'D:\portable\knitcalc\knitcalc.exe',
          readInstallSource: (_) => 'something-else',
        ),
        Channel.windowsPortable,
      );
    });

    test('reads the marker from the executable directory', () {
      String? captured;
      windowsChannelForExecutable(
        r'C:\Users\me\AppData\Local\Programs\KnitCalc\knitcalc.exe',
        readInstallSource: (dir) {
          captured = dir;
          return null;
        },
      );
      expect(captured, r'C:\Users\me\AppData\Local\Programs\KnitCalc');
    });

    test('does not consult the marker for scoop or chocolatey installs', () {
      var consulted = false;
      String? marker(String _) {
        consulted = true;
        return 'winget';
      }

      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\scoop\apps\knitcalc\current\knitcalc.exe',
          readInstallSource: marker,
        ),
        Channel.windowsScoop,
      );
      expect(
        windowsChannelForExecutable(
          r'C:\ProgramData\chocolatey\lib\knitcalc\tools\knitcalc.exe',
          readInstallSource: marker,
        ),
        Channel.windowsChocolatey,
      );
      expect(consulted, isFalse);
    });
  });

  group('macosChannelForExecutable', () {
    test('maps a Caskroom path to macosHomebrew', () {
      expect(
        macosChannelForExecutable(
          '/opt/homebrew/Caskroom/knitcalc/1.8.8/KnitCalc.app/Contents/MacOS/knitcalc',
        ),
        Channel.macosHomebrew,
      );
    });

    test('maps a plain /Applications path to macosManual', () {
      expect(
        macosChannelForExecutable(
          '/Applications/KnitCalc.app/Contents/MacOS/knitcalc',
        ),
        Channel.macosManual,
      );
    });
  });

  group('linuxIsSystemInstall', () {
    test('treats a /usr prefix as a system (apt/dpkg) install', () {
      expect(linuxIsSystemInstall('/usr/bin/knitcalc'), isTrue);
      expect(linuxIsSystemInstall('/usr/lib/knitcalc/knitcalc'), isTrue);
    });

    test('treats home/opt installs as not system-managed', () {
      expect(linuxIsSystemInstall('/home/me/knitcalc/knitcalc'), isFalse);
      expect(linuxIsSystemInstall('/opt/knitcalc/knitcalc'), isFalse);
    });
  });
}
