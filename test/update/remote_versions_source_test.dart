import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';

void main() {
  group('fetchStoreVersions', () {
    test('decodes the document on 200', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'fields': {
              'android': {
                'mapValue': {
                  'fields': {
                    'version': {'stringValue': '1.9.0+70'},
                    'url': {'stringValue': 'https://cdn.example.com/app.apk'},
                  },
                },
              },
            },
          }),
          200,
        ),
      );

      final versions = await fetchStoreVersions(client: client);

      expect(versions['android']?.version.toString(), '1.9.0+70');
    });

    test(
      'returns an empty map when the document does not exist (404)',
      () async {
        final client = MockClient((_) async => http.Response('{}', 404));

        expect(await fetchStoreVersions(client: client), isEmpty);
      },
    );

    test('throws on a non-200/404 response (unreachable / blocked)', () async {
      final client = MockClient((_) async => http.Response('robot', 403));

      expect(
        fetchStoreVersions(client: client),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws when the request itself fails (offline)', () async {
      final client = MockClient((_) async => throw const SocketishError());

      expect(
        fetchStoreVersions(client: client),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });
}

/// A stand-in transport error (MockClient has no real socket to fail).
class SocketishError implements Exception {
  const SocketishError();
}
