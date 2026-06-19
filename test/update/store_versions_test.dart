import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';

/// A Firestore REST document carrying a bare-string store entry and a map
/// self-update entry, plus a malformed entry that must be skipped.
Map<String, dynamic> _document() => {
  'name':
      'projects/knitcalc-sync/databases/(default)/documents/config/storeVersions',
  'fields': {
    'fdroid': {'stringValue': '1.9.0+60'},
    'android': {
      'mapValue': {
        'fields': {
          'version': {'stringValue': '1.9.0+60'},
          'url': {'stringValue': 'https://cdn.example.com/app.apk'},
          'size': {'integerValue': '12582912'},
          'notes': {'stringValue': 'What is new'},
        },
      },
    },
    'broken': {'stringValue': 'not-a-version!!'},
  },
};

void main() {
  group('decodeStoreVersions', () {
    test('decodes a bare-string store entry', () {
      final entries = decodeStoreVersions(_document());

      final fdroid = entries['fdroid'];
      expect(fdroid, isNotNull);
      expect(fdroid!.version, const AppVersion(1, 9, 0, 60));
      expect(fdroid.label, '1.9.0+60');
      expect(fdroid.url, isNull);
      expect(fdroid.size, isNull);
    });

    test('decodes a self-update map entry with url/size/notes', () {
      final android = decodeStoreVersions(_document())['android'];

      expect(android, isNotNull);
      expect(android!.version, const AppVersion(1, 9, 0, 60));
      expect(android.url, 'https://cdn.example.com/app.apk');
      expect(android.size, 12582912);
      expect(android.notes, 'What is new');
    });

    test('skips entries whose version cannot be parsed', () {
      expect(decodeStoreVersions(_document()).containsKey('broken'), isFalse);
    });

    test('returns empty for a document without fields', () {
      expect(decodeStoreVersions(const {}), isEmpty);
    });
  });

  group('evaluateRemoteUpdate', () {
    const entry = RemoteEntry(
      version: AppVersion(1, 9, 0),
      label: '1.9.0',
      url: 'https://cdn.example.com/app.apk',
      size: 99,
      notes: 'Notes',
    );

    test('returns info carrying the entry payload when newer', () {
      final info = evaluateRemoteUpdate(
        const AppVersion(1, 8, 0),
        entry,
        action: UpdateAction.inApp,
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 9, 0));
      expect(info.versionLabel, '1.9.0');
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://cdn.example.com/app.apk');
      expect(info.downloadSize, 99);
      expect(info.releaseNotes, 'Notes');
    });

    test('lets a url override the entry url (store listing)', () {
      final info = evaluateRemoteUpdate(
        const AppVersion(1, 8, 0),
        entry,
        action: UpdateAction.openUrl,
        url: 'https://f-droid.org/packages/io.github.dmezhnov.knitcalc/',
      );

      expect(
        info!.url,
        'https://f-droid.org/packages/io.github.dmezhnov.knitcalc/',
      );
    });

    test('returns null when not newer', () {
      expect(
        evaluateRemoteUpdate(
          const AppVersion(1, 9, 0),
          entry,
          action: UpdateAction.inApp,
        ),
        isNull,
      );
    });

    test('returns null for a missing entry or unknown current version', () {
      expect(
        evaluateRemoteUpdate(
          const AppVersion(1, 0, 0),
          null,
          action: UpdateAction.inApp,
        ),
        isNull,
      );
      expect(
        evaluateRemoteUpdate(null, entry, action: UpdateAction.inApp),
        isNull,
      );
    });
  });

  group('storeVersionsUrl', () {
    test('targets the public config document with the api key', () {
      final url = storeVersionsUrl(firebaseConfig).toString();

      expect(url, contains('/documents/config/storeVersions'));
      expect(url, contains('projects/${firebaseConfig.projectId}'));
      expect(url, contains('key=${firebaseConfig.apiKey}'));
    });
  });
}
