import 'dart:convert';
import 'dart:io';

/// Local HTTP stand-in for the GitHub Releases API, used by the desktop update
/// service tests instead of reaching out to the network.
///
/// Serves the `releases/latest` payload at [releaseUrl] and a single downloadable
/// asset at [assetUrl] (referenced from the payload's `browser_download_url`).
/// The asset response carries an explicit `Content-Length` so the service's
/// progress callback fires. [assetRequests] records how many times the asset was
/// fetched.
class FakeReleaseServer {
  FakeReleaseServer._(
    this._server, {
    required this.tag,
    required this.assetName,
    required this.assetBytes,
    required this.releaseStatus,
    required this.assetStatus,
  }) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final String tag;
  final String assetName;
  final List<int> assetBytes;
  final int releaseStatus;
  final int assetStatus;

  int assetRequests = 0;

  static Future<FakeReleaseServer> start({
    String tag = 'v9.9.9+0',
    required String assetName,
    List<int> assetBytes = const <int>[],
    int releaseStatus = 200,
    int assetStatus = 200,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    return FakeReleaseServer._(
      server,
      tag: tag,
      assetName: assetName,
      assetBytes: assetBytes,
      releaseStatus: releaseStatus,
      assetStatus: assetStatus,
    );
  }

  String get _base => 'http://${_server.address.host}:${_server.port}';

  Uri get releaseUrl => Uri.parse('$_base/release');

  String get assetUrl => '$_base/asset';

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;

    switch (request.uri.path) {
      case '/release':
        response.statusCode = releaseStatus;
        if (releaseStatus == 200) {
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'tag_name': tag,
              'body': 'Release notes',
              'assets': [
                {'name': assetName, 'browser_download_url': assetUrl},
              ],
            }),
          );
        }
      case '/asset':
        assetRequests++;
        response.statusCode = assetStatus;
        if (assetStatus == 200) {
          response.contentLength = assetBytes.length;
          response.add(assetBytes);
        }
      default:
        response.statusCode = HttpStatus.notFound;
    }

    await response.close();
  }
}
