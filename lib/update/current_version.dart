import 'package:knitcalc/update/app_version.dart';

/// The running build's version, baked in at build time via
/// `--dart-define=APP_VERSION=<pubspec version>` (see the `build-web` task).
///
/// The define is empty under `flutter run`, in tests, and in any build that
/// does not pass it; callers then skip update checks because there is no
/// reliable baseline to compare a deployed version against.
const String _appVersionDefine = String.fromEnvironment('APP_VERSION');

/// The current build's version, or null when [_appVersionDefine] was not set.
AppVersion? currentAppVersion() => AppVersion.tryParse(_appVersionDefine);
