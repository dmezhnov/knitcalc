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

/// Supplies the decoded channel entries. Injected so services can be tested
/// without a network or a real Firestore.
///
/// Returns the channel map (empty when the document does not exist yet), and
/// throws [UpdateCheckException] when the source could not be reached — so a
/// genuine "no update" is distinguishable from a network failure that should
/// surface a retryable error to the user.
typedef RemoteVersionsFetcher = Future<Map<String, RemoteEntry>> Function();

/// Thrown when the store-versions check could not reach its source (offline,
/// blocked, or a server error). Callers treat this as a transient network
/// problem rather than "up to date".
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Default fetcher: GETs the public store-versions document and decodes it.
///
/// A `404` means the document has not been seeded yet — a reachable source with
/// no entries, so it returns an empty map (no update, no error). Any other
/// failure (network error, non-200, malformed body) throws
/// [UpdateCheckException] so the caller can offer the user a retry.
Future<Map<String, RemoteEntry>> fetchStoreVersions({
  http.Client? client,
  FirebaseConfig config = firebaseConfig,
}) async {
  final http_ = client ?? http.Client();

  try {
    final response = await http_.get(
      storeVersionsUrl(config),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode == 404) {
      return const {};
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException('HTTP ${response.statusCode}');
    }

    final document = jsonDecode(response.body) as Map<String, dynamic>;

    return decodeStoreVersions(document);
  } on UpdateCheckException {
    rethrow;
  } on Object catch (error) {
    throw UpdateCheckException('$error');
  } finally {
    if (client == null) {
      http_.close();
    }
  }
}
