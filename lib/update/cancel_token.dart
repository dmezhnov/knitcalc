import 'dart:async';

/// Cooperative cancellation for an in-flight update download.
///
/// The progress dialog's Cancel button (and a back-press) trips it; a
/// downloading [UpdateService] watches [whenCancelled] to abort the transfer
/// promptly instead of running to completion. Passing no token (the default)
/// means the download can't be cancelled, as before.
class CancelToken {
  final Completer<void> _completer = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Completes once [cancel] is called; never completes otherwise.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _completer.complete();
  }
}

/// Raised by a download aborted through its [CancelToken], so the caller can
/// tell a user cancel from a real failure and skip the error snackbar.
class UpdateCancelled implements Exception {
  const UpdateCancelled();

  @override
  String toString() => 'UpdateCancelled';
}
