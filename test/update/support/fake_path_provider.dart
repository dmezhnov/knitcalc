import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Test stand-in for path_provider so the update services can call
/// `getTemporaryDirectory()` on the VM, where no plugin is registered.
///
/// Only [getTemporaryPath] is exercised; the rest stay unimplemented.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.temporaryPath);

  final String temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}
