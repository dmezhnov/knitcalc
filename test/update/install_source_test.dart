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
}
