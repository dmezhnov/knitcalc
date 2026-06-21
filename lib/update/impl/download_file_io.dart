import 'dart:async';
import 'dart:io';

import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';

/// Downloads [url] into [dest], reporting progress and honouring [control].
///
/// Shared by the desktop self-updaters (Windows/Linux/macOS), which only differ
/// in what they do with the finished archive. The transfer is:
///   * **cancellable** — when [control] trips, the partial file is deleted and
///     [UpdateCancelled] is thrown;
///   * **pausable** — on pause the open connection is dropped but the partial
///     file is kept; on resume a `Range` request continues from where it stopped
///     (GitHub's CDN serves ranges). If the server ignores the range and replies
///     `200`, the download safely restarts from zero.
///
/// Passing no [control] downloads straight through, as before.
Future<void> downloadFileWithControl({
  required HttpClient client,
  required Uri url,
  required File dest,
  UpdateProgressCallback? onProgress,
  DownloadControl? control,
}) async {
  var received = 0;
  var total = -1;

  // Drop any stale partial from a previous run so a fresh start writes cleanly.
  await _deleteQuietly(dest);

  // One pass per connection: the normal case runs the loop once; a pause ends a
  // pass and the next pass resumes with a Range request from `received`.
  while (true) {
    if (control?.isCancelled ?? false) {
      await _deleteQuietly(dest);
      throw const UpdateCancelled();
    }

    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'knitcalc-updater');
    if (received > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$received-');
    }

    final response = await request.close();
    final resuming = received > 0;

    if (resuming) {
      if (response.statusCode != HttpStatus.partialContent) {
        // Server ignored the range: restart the whole download from scratch.
        received = 0;
        await _deleteQuietly(dest);
      }
    } else if (response.statusCode != HttpStatus.ok) {
      await _deleteQuietly(dest);
      throw HttpException('Download failed with status ${response.statusCode}');
    }

    // contentLength is the bytes in *this* response; add what we already have to
    // get the full size. -1 (omitted) leaves total unknown → indeterminate UI.
    total = response.contentLength >= 0
        ? received + response.contentLength
        : -1;

    final sink = dest.openWrite(mode: FileMode.append);

    // Completes true when the body finished, false when paused mid-stream.
    final done = Completer<bool>();
    late final StreamSubscription<List<int>> sub;
    StreamSubscription<void>? cancelWatch;
    void Function()? pauseListener;

    sub = response.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(DownloadProgress(received: received, total: total));
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete(true);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      cancelOnError: true,
    );

    if (control != null) {
      cancelWatch = control.whenCancelled.asStream().listen((_) {
        if (!done.isCompleted) done.completeError(const UpdateCancelled());
      });
      pauseListener = () {
        if (control.isPaused && !done.isCompleted) {
          done.complete(false);
        }
      };
      control.pausedListenable.addListener(pauseListener);
    }

    bool finished;
    try {
      finished = await done.future;
    } catch (_) {
      await cancelWatch?.cancel();
      if (pauseListener != null) {
        control!.pausedListenable.removeListener(pauseListener);
      }
      await sub.cancel();
      await sink.close();
      await _deleteQuietly(dest);
      rethrow;
    }

    await cancelWatch?.cancel();
    if (pauseListener != null) {
      control!.pausedListenable.removeListener(pauseListener);
    }
    await sub.cancel();
    await sink.close();

    if (finished) {
      return;
    }

    // Paused: keep the partial file and wait for resume (or cancel) before the
    // next pass re-requests from `received`.
    await control?.waitWhilePaused();
    if (control?.isCancelled ?? false) {
      await _deleteQuietly(dest);
      throw const UpdateCancelled();
    }
  }
}

Future<void> _deleteQuietly(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
