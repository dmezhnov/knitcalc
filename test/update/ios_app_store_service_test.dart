import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/store/ios_app_store_service.dart';
import 'package:knitcalc/update/update_info.dart';

http.Client _client(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

String _lookupJson({String version = '1.9.0', int trackId = 42}) => jsonEncode({
  'resultCount': 1,
  'results': [
    {
      'version': version,
      'trackId': trackId,
      'trackViewUrl': 'https://apps.apple.com/app/id$trackId',
    },
  ],
});

void main() {
  const current = AppVersion(1, 8, 0);

  group('checkForUpdate', () {
    test('returns an openUrl update when the live version is newer', () async {
      final service = IosAppStoreService(
        current: current,
        httpClient: _client(_lookupJson()),
        launchUrl: (_) async => true,
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.action, UpdateAction.openUrl);
      expect(info.versionLabel, '1.9.0');
    });

    test('returns null when the live version is not newer', () async {
      final service = IosAppStoreService(
        current: current,
        httpClient: _client(_lookupJson(version: '1.8.0')),
        launchUrl: (_) async => true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the app is not on the store', () async {
      final service = IosAppStoreService(
        current: current,
        httpClient: _client(jsonEncode({'resultCount': 0, 'results': []})),
        launchUrl: (_) async => true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null on an HTTP error rather than throwing', () async {
      final service = IosAppStoreService(
        current: current,
        httpClient: _client('nope', status: 500),
        launchUrl: (_) async => true,
      );

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('startUpdate', () {
    test('opens the deep link first, then falls back to https', () async {
      final opened = <Uri>[];
      final service = IosAppStoreService(
        current: current,
        httpClient: _client(_lookupJson()),
        launchUrl: (url) async {
          opened.add(url);
          return url.scheme == 'https';
        },
      );

      final info = await service.checkForUpdate();
      await service.startUpdate(info!);

      expect(opened.first.scheme, 'itms-apps');
      expect(opened.last.scheme, 'https');
    });

    test('throws when no listing can be opened', () async {
      final service = IosAppStoreService(
        current: current,
        httpClient: _client(_lookupJson()),
        launchUrl: (_) async => false,
      );

      final info = await service.checkForUpdate();

      await expectLater(service.startUpdate(info!), throwsStateError);
    });
  });
}
