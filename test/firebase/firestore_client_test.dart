import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/firebase/firestore_client.dart';
import 'package:knitcalc/storage/saved_project.dart';

void main() {
  const config = FirebaseConfig(projectId: 'proj', apiKey: 'KEY');

  Map<String, dynamic> doc(String id, String name, String updatedAt) => {
    'name':
        'projects/proj/databases/(default)/documents/users/uid1/projects/$id',
    'fields': {
      'name': {'stringValue': name},
      'productId': {'stringValue': 'rectangular_scarf'},
      'description': {'stringValue': ''},
      'updatedAt': {'timestampValue': updatedAt},
      'values': {'mapValue': <String, dynamic>{}},
      'photos': {'arrayValue': <String, dynamic>{}},
    },
  };

  FirestoreClient client(
    MockClientHandler handler, {
    Future<String?> Function()? token,
  }) {
    return FirestoreClient(
      config: config,
      tokenProvider: token ?? () async => 'TOKEN',
      httpClient: MockClient(handler),
    );
  }

  test('listProjects follows pagination and decodes documents', () async {
    final c = client((request) async {
      expect(request.headers['Authorization'], 'Bearer TOKEN');
      final page = request.url.queryParameters['pageToken'];
      if (page == null) {
        return http.Response(
          jsonEncode({
            'documents': [doc('1', 'A', '2026-06-01T00:00:00Z')],
            'nextPageToken': 'PAGE2',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'documents': [doc('2', 'B', '2026-06-02T00:00:00Z')],
        }),
        200,
      );
    });

    final all = await c.listProjects('uid1');

    expect(all.map((p) => p.id), ['1', '2']);
    expect(all.map((p) => p.name), ['A', 'B']);
  });

  test(
    'listProjects returns empty for a collection with no documents',
    () async {
      final c = client((request) async => http.Response('{}', 200));

      expect(await c.listProjects('uid1'), isEmpty);
    },
  );

  test('putProject patches the right document with encoded fields', () async {
    late Uri calledUri;
    late Map<String, dynamic> sentBody;
    final c = client((request) async {
      calledUri = request.url;
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(doc('9', 'X', '2026-06-07T00:00:00Z')),
        200,
      );
    });

    await c.putProject(
      'uid1',
      SavedProject(
        id: '9',
        name: 'X',
        productId: 'rectangular_scarf',
        values: const {'a': '1'},
        updatedAt: DateTime.utc(2026, 6, 7),
      ),
    );

    expect(calledUri.path, endsWith('/users/uid1/projects/9'));
    expect(sentBody['fields']['name']['stringValue'], 'X');
    expect(
      sentBody['fields']['values']['mapValue']['fields']['a']['stringValue'],
      '1',
    );
  });

  test('throws when there is no auth token', () async {
    final c = client(
      (request) async => http.Response('{}', 200),
      token: () async => null,
    );

    await expectLater(
      c.listProjects('uid1'),
      throwsA(isA<FirestoreException>()),
    );
  });

  test('surfaces HTTP errors', () async {
    final c = client(
      (request) async =>
          http.Response('{"error":{"message":"PERMISSION"}}', 403),
    );

    await expectLater(
      c.listProjects('uid1'),
      throwsA(isA<FirestoreException>()),
    );
  });
}
