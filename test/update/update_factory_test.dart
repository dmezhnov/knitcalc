import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/update_factory.dart';

void main() {
  // Only the no-sideload build (`mise build apk-nosideload`, for catalogues
  // that reject REQUEST_INSTALL_PACKAGES) turns the sideload installer off,
  // with --dart-define=KNITCALC_SIDELOAD_INSTALL=false; see packaging/README.md.
  // If the default ever flipped, every sideloaded install would silently stop
  // self-updating, which no test would otherwise notice.
  test('sideload self-update is on unless the build opts out', () {
    expect(sideloadInstallSupported, isTrue);
  });
}
