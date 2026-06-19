/// Fetches and decodes the public store-versions document over Firestore REST.
///
/// This is the single source every update service now reads instead of polling
/// the GitHub API (see store_versions.dart for why). The read is
/// unauthenticated — a public read rule on `config/{doc}` plus the shipped API
/// key — so it works on every platform and before sign-in.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';

/// Supplies the decoded channel entries, or `null` when they cannot be fetched
/// (offline, throttled, missing document). Injected so services can be tested
/// without a network or a real Firestore.
typedef RemoteVersionsFetcher = Future<Map<String, RemoteEntry>?> Function();

/// Default fetcher: GETs the public store-versions document and decodes it.
///
/// Returns `null` on any failure (network error, non-200, malformed body) so
/// callers degrade to "no update found" and retry on the next launch — the
/// same graceful behaviour the GitHub-polling services had.
Future<Map<String, RemoteEntry>?> fetchStoreVersions({
  http.Client? client,
  FirebaseConfig config = firebaseConfig,
}) async {
  final http_ = client ?? http.Client();

  try {
    final response = await http_.get(
      storeVersionsUrl(config),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      return null;
    }

    final document = jsonDecode(response.body) as Map<String, dynamic>;

    return decodeStoreVersions(document);
  } on Object {
    return null;
  } finally {
    if (client == null) {
      http_.close();
    }
  }
}
