import 'package:url_launcher/url_launcher.dart' as launcher;

/// Opens [url] in an external application (the store app or the browser),
/// returning whether it could be launched. Injected in tests.
typedef UrlLauncher = Future<bool> Function(Uri url);

/// Default launcher: hands the URL to the platform's external handler.
Future<bool> launchExternal(Uri url) =>
    launcher.launchUrl(url, mode: launcher.LaunchMode.externalApplication);

/// Tries [urls] in order and returns `true` at the first that launches.
///
/// A native deep link (e.g. `itms-apps://`) is expected first, followed by an
/// https fallback. A launch that returns `false` or throws (unhandled scheme,
/// no store app) is skipped and the next URL is tried; returns `false` when
/// none can be opened.
Future<bool> launchFirstAvailable(List<Uri> urls, UrlLauncher launch) async {
  for (final url in urls) {
    try {
      if (await launch(url)) {
        return true;
      }
    } on Object {
      // Scheme unhandled / store app missing: fall through to the next URL.
    }
  }

  return false;
}
