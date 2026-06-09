/// Outcome of [savePhoto] (see photo_download.dart), shared by every platform
/// variant so the caller can tell a real failure from a user cancellation (the
/// desktop "Save As" dialog can be dismissed) and show the right feedback.
library;

enum PhotoSaveStatus {
  /// The photo was written. [PhotoSaveResult.path] holds a user-visible path
  /// when there is one (desktop), or is null when there isn't (web download,
  /// mobile gallery).
  saved,

  /// The user dismissed the save dialog; nothing was written and no error.
  cancelled,

  /// The save was attempted but failed.
  failed,
}

class PhotoSaveResult {
  const PhotoSaveResult(this.status, [this.path]);

  final PhotoSaveStatus status;

  /// The saved file's path, when meaningful (desktop "Save As"); null otherwise.
  final String? path;
}
