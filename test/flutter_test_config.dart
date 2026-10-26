import 'dart:async';
import 'dart:io';

import 'package:knitcalc/products/products.dart';

/// flutter_test runs this around every test file under test/. The app loads
/// its products in main(), which tests skip by pumping MyApp directly, so the
/// same files are loaded here — straight from disk rather than through
/// rootBundle, because the asset bundle needs a test binding, and some tests
/// deliberately run without one (it stubs out real HTTP).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadProducts((path) => File(path).readAsString());
  await testMain();
}
