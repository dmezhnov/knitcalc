import 'dart:convert';
import 'dart:js_interop';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/web/web_update_logic.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:web/web.dart' as web;

UpdateService createWebUpdateService(AppVersion? current) =>
    WebUpdateService(current);

/// Web update mechanism.
///
/// Flutter's web build ships a `version.json` describing the deployed version.
/// We fetch it with caching disabled and compare it to the running build; when
/// the deployment is newer we offer a reload, which pulls the fresh assets.
/// The self-unregistering service worker clears any stale caches on activate,
/// so a plain reload is enough to pick up the new build.
class WebUpdateService implements UpdateService {
  WebUpdateService(this._current, {String versionUrl = 'version.json'})
    : _versionUrl = versionUrl;

  final AppVersion? _current;
  final String _versionUrl;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    if (_current == null) {
      return null;
    }

    final Map<String, dynamic> payload;
    try {
      payload = await _fetchVersionJson();
    } catch (_) {
      // Offline or a transient failure: treat as "no update available".
      return null;
    }

    return evaluateWebUpdate(_current, payload);
  }

  @override
  Future<void> startUpdate(UpdateInfo info) async {
    // Force a full reload so the browser pulls the freshly deployed assets.
    web.window.location.reload();
  }

  Future<Map<String, dynamic>> _fetchVersionJson() async {
    // Cache-bust so we read the deployed file, not the copy the browser cached
    // alongside the page when this build first loaded.
    final url = '$_versionUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    final response = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart;
    final body = await response.text().toDart;

    return jsonDecode(body.toDart) as Map<String, dynamic>;
  }
}
