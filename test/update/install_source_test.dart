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
    test('maps a WinGet\\Packages path to windowsWinget', () {
      expect(
        windowsChannelForExecutable(
          r'C:\Users\me\AppData\Local\Microsoft\WinGet\Packages\Dmezhnov.KnitCalc_x\knitcalc.exe',
        ),
        Channel.windowsWinget,
      );
    });

    test('is case-insensitive and tolerates forward slashes', () {
      expect(
        windowsChannelForExecutable(
          'C:/Users/me/AppData/Local/Microsoft/winget/packages/X/knitcalc.exe',
        ),
        Channel.windowsWinget,
      );
    });

    test('maps anything else to windowsManual', () {
      expect(
        windowsChannelForExecutable(r'C:\Program Files\KnitCalc\knitcalc.exe'),
        Channel.windowsManual,
      );
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
