import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cooperative control for an in-flight update download: cancel and pause/resume.
///
/// The progress dialog's buttons (and a back-press) drive it; a downloading
/// [UpdateService] watches it to abort or pause the transfer promptly instead of
/// running straight to completion. Passing no control (the default) means the
/// download can't be cancelled or paused, as before.
class DownloadControl {
  final Completer<void> _cancelled = Completer<void>();
  final ValueNotifier<bool> _paused = ValueNotifier<bool>(false);

  // Recreated on each pause; completed on resume (or cancel) to unblock anyone
  // awaiting [waitWhilePaused].
  Completer<void>? _resume;

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes once [cancel] is called; never completes otherwise.
  Future<void> get whenCancelled => _cancelled.future;

  bool get isPaused => _paused.value;

  /// Tracks the paused state so the dialog can swap its Pause/Resume button.
  ValueListenable<bool> get pausedListenable => _paused;

  void cancel() {
    if (_cancelled.isCompleted) {
      return;
    }
    _cancelled.complete();
    // A paused download must be unblocked so it can observe the cancel and abort.
    _clearPause();
  }

  void pause() {
    if (_cancelled.isCompleted || _paused.value) {
      return;
    }
    _resume = Completer<void>();
    _paused.value = true;
  }

  void resume() {
    if (!_paused.value) {
      return;
    }
    _clearPause();
  }

  /// Resolves immediately when not paused; otherwise once [resume] (or [cancel])
  /// is called. A download loop awaits this between chunks to honour a pause.
  Future<void> waitWhilePaused() {
    final resume = _resume;
    if (!_paused.value || resume == null) {
      return Future<void>.value();
    }
    return resume.future;
  }

  void _clearPause() {
    _paused.value = false;
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) {
      resume.complete();
    }
  }

  void dispose() {
    _paused.dispose();
  }
}

/// Raised by a download aborted through its [DownloadControl], so the caller can
/// tell a user cancel from a real failure and skip the error snackbar.
class UpdateCancelled implements Exception {
  const UpdateCancelled();

  @override
  String toString() => 'UpdateCancelled';
}
