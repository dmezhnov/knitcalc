/// Minimal Firestore REST client for the saved-projects collection.
///
/// Documents live at `users/{uid}/projects/{projectId}`. The client authorizes
/// every call with a bearer id token obtained from [tokenProvider] (typically
/// `AuthService.freshIdToken`) and exchanges [SavedProject]s via
/// firestore_codec. It is deliberately tiny: list and upsert are all the sync
/// engine needs — deletions are upserts of a tombstone.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/saved_project.dart';
import 'firebase_config.dart';
import 'firestore_codec.dart';

/// Raised when a Firestore REST call fails or when no auth token is available.
class FirestoreException implements Exception {
  const FirestoreException(this.message);

  final String message;

  @override
  String toString() => 'FirestoreException($message)';
}

/// The slice of remote storage the sync engine needs, so it can be faked in
/// tests without a real [FirestoreClient].
abstract interface class RemoteProjects {
  Future<List<SavedProject>> listProjects(String uid);
  Future<void> putProject(String uid, SavedProject project);
}

class FirestoreClient implements RemoteProjects {
  FirestoreClient({
    required this.config,
    required this.tokenProvider,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final FirebaseConfig config;

  /// Supplies a currently-valid id token, or `null` when signed out.
  final Future<String?> Function() tokenProvider;

  /// Per-request deadline. A blocked/blackholed network (e.g. an ISP that drops
  /// firestore.googleapis.com) otherwise stalls the call indefinitely, so the
  /// sync neither succeeds nor surfaces an error. Injectable for tests.
  final Duration timeout;

  final http.Client _http;

  String get _documentsBase =>
      'https://firestore.googleapis.com/v1/projects/${config.projectId}'
      '/databases/(default)/documents';

  /// Returns every project document for [uid], including tombstones, following
  /// pagination until exhausted.
  @override
  Future<List<SavedProject>> listProjects(String uid) async {
    final token = await _requireToken();
    final projects = <SavedProject>[];
    String? pageToken;

    do {
      final uri = Uri.parse(
        '$_documentsBase/users/$uid/projects',
      ).replace(queryParameters: {'pageSize': '300', 'pageToken': ?pageToken});

      final response = await _send(
        () => _http.get(uri, headers: _authHeader(token)),
      );
      final json = _decode(response);
      final documents = json['documents'] as List<dynamic>? ?? const [];

      for (final document in documents) {
        projects.add(decodeProjectDocument(document as Map<String, dynamic>));
      }

      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null);

    return projects;
  }

  /// Creates or overwrites the document for [project] under [uid].
  @override
  Future<void> putProject(String uid, SavedProject project) async {
    final token = await _requireToken();
    final uri = Uri.parse('$_documentsBase/users/$uid/projects/${project.id}');

    final response = await _send(
      () => _http.patch(
        uri,
        headers: {..._authHeader(token), 'Content-Type': 'application/json'},
        body: jsonEncode(encodeProjectFields(project)),
      ),
    );

    _decode(response);
  }

  /// Runs an HTTP call with the request [timeout], translating any transport
  /// failure or timeout into a [FirestoreException]. Without this a raw
  /// `SocketException`/`TimeoutException` escapes the sync's `on
  /// FirestoreException` handler, so a blocked network neither syncs nor shows
  /// the offline banner.
  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on Object catch (error) {
      throw FirestoreException('network error: $error');
    }
  }

  Future<String> _requireToken() async {
    final String? token;
    try {
      token = await tokenProvider();
    } on FirestoreException {
      rethrow;
    } on Object catch (error) {
      // A token refresh on a blocked network can fail/time out; surface it as a
      // FirestoreException so the caller shows the offline banner (and is not
      // signed out — that only happens on a real auth error inside the provider).
      throw FirestoreException('auth error: $error');
    }

    if (token == null) {
      throw const FirestoreException('not signed in');
    }

    return token;
  }

  Map<String, String> _authHeader(String token) => {
    'Authorization': 'Bearer $token',
  };

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw FirestoreException('HTTP ${response.statusCode}: ${response.body}');
    }

    if (response.body.isEmpty) {
      return const {};
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
