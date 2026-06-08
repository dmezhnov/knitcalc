import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/store/itunes_lookup.dart';
import 'package:knitcalc/update/update_info.dart';

Map<String, dynamic> _lookup({
  String? version = '1.9.0',
  int? trackId = 123456789,
  String? trackViewUrl = 'https://apps.apple.com/app/id123456789',
  bool empty = false,
}) => {
  'resultCount': empty ? 0 : 1,
  'results': empty
      ? <Map<String, dynamic>>[]
      : [
          {
            'version': ?version,
            'trackId': ?trackId,
            'trackViewUrl': ?trackViewUrl,
          },
        ],
};

void main() {
  group('itunesLookupUrl', () {
    test('targets the lookup endpoint with the bundle id', () {
      final url = itunesLookupUrl('com.x.y');

      expect(url.host, 'itunes.apple.com');
      expect(url.path, '/lookup');
      expect(url.queryParameters['bundleId'], 'com.x.y');
      expect(url.queryParameters.containsKey('country'), isFalse);
    });

    test('scopes to a storefront when a country is given', () {
      final url = itunesLookupUrl('com.x.y', country: 'ru');
      expect(url.queryParameters['country'], 'ru');
    });
  });

  group('parseItunesLookup', () {
    test('reads version, track id and listing url from the first result', () {
      final result = parseItunesLookup(_lookup());

      expect(result, isNotNull);
      expect(result!.version, '1.9.0');
      expect(result.trackId, 123456789);
      expect(result.trackViewUrl, 'https://apps.apple.com/app/id123456789');
    });

    test('returns null when the app is not on the store', () {
      expect(parseItunesLookup(_lookup(empty: true)), isNull);
    });

    test('returns null when the result has no version', () {
      expect(parseItunesLookup(_lookup(version: null)), isNull);
    });
  });

  group('appStoreUrls', () {
    test('puts the itms-apps deep link before the https fallback', () {
      final urls = appStoreUrls(parseItunesLookup(_lookup())!);

      expect(urls, hasLength(2));
      expect(urls.first.scheme, 'itms-apps');
      expect(urls.first.toString(), contains('id123456789'));
      expect(urls.last.scheme, 'https');
    });

    test('omits the deep link when there is no track id', () {
      final urls = appStoreUrls(parseItunesLookup(_lookup(trackId: null))!);

      expect(urls, hasLength(1));
      expect(urls.single.scheme, 'https');
    });
  });

  group('evaluateItunesUpdate', () {
    const current = AppVersion(1, 8, 0);

    test('returns an openUrl update with the live version when newer', () {
      final info = evaluateItunesUpdate(current, _lookup());

      expect(info, isNotNull);
      expect(info!.action, UpdateAction.openUrl);
      expect(info.versionLabel, '1.9.0');
      expect(info.latestVersion, const AppVersion(1, 9, 0));
      // The https listing is kept as the reference url.
      expect(info.url, contains('apps.apple.com'));
    });

    test('returns null when the live version is not newer', () {
      expect(evaluateItunesUpdate(current, _lookup(version: '1.8.0')), isNull);
      expect(evaluateItunesUpdate(current, _lookup(version: '1.0.0')), isNull);
    });

    test('returns null when the app is not on the store', () {
      expect(evaluateItunesUpdate(current, _lookup(empty: true)), isNull);
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateItunesUpdate(null, _lookup()), isNull);
    });
  });
}
