import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/impl/download_file_io.dart';

void main() {
  // A deterministic 2 MB payload (value = index mod 256). Large enough that the
  // client reads it in several chunks, so a pause/cancel lands mid-stream rather
  // than after the whole body arrives at once over loopback.
  final content = List<int>.generate(2 * 1024 * 1024, (i) => i % 256);

  late HttpServer server;
  late Directory tmp;
  late Uri url;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('knitcalc-dl-test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://${server.address.host}:${server.port}/file');

    server.listen((request) async {
      final response = request.response;
      final range = request.headers.value(HttpHeaders.rangeHeader);

      if (range != null) {
        // Resume request: serve the remaining bytes from the requested offset.
        final start = int.parse(
          RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
        );
        final rest = content.sublist(start);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${content.length - 1}/${content.length}',
        );
        response.contentLength = rest.length;
        response.add(rest);
        await response.close();
        return;
      }

      // Initial request: send the whole body. At this size the client reads it
      // in several chunks, so a pause/cancel interrupts it mid-flight; dropping
      // the connection then surfaces here as a write error.
      response.contentLength = content.length;
      try {
        response.add(content);
        await response.close();
      } catch (_) {
        // Client disconnected (paused/cancelled): nothing more to send.
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('downloads the whole file', () async {
    final dest = File('${tmp.path}/out.bin');
    await downloadFileWithControl(client: HttpClient(), url: url, dest: dest);

    expect(dest.readAsBytesSync(), content);
  });

  test('cancel aborts and deletes the partial file', () async {
    final dest = File('${tmp.path}/out.bin');
    final control = DownloadControl();

    await expectLater(
      downloadFileWithControl(
        client: HttpClient(),
        url: url,
        dest: dest,
        control: control,
        // Cancel as soon as the first bytes land.
        onProgress: (_) => control.cancel(),
      ),
      throwsA(isA<UpdateCancelled>()),
    );

    expect(dest.existsSync(), isFalse);
  });

  test('pause then resume continues via a Range request and completes', () async {
    final dest = File('${tmp.path}/out.bin');
    final control = DownloadControl();
    var paused = false;

    await downloadFileWithControl(
      client: HttpClient(),
      url: url,
      dest: dest,
      control: control,
      onProgress: (p) {
        // Pause once, partway through, then resume shortly after. Resume issues
        // a Range request from wherever the transfer got to.
        if (!paused && p.received > 0) {
          paused = true;
          control.pause();
          Future<void>.delayed(
            const Duration(milliseconds: 30),
            control.resume,
          );
        }
      },
    );

    // The whole file is present and correct despite the pause/resume.
    expect(dest.readAsBytesSync(), content);
  });
}
