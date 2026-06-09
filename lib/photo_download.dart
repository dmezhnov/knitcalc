/// Saves an attached photo out of the app to a platform-appropriate place,
/// reusing only packages already in the project (plus file_selector, whose
/// platform implementations are already pulled in transitively):
///
/// - **Web** triggers a normal browser download via an object-URL anchor.
/// - **Android / iOS** save the JPEG into the device gallery (Android
///   MediaStore / iOS Photos) through the native method channel.
/// - **Desktop** shows a native "Save As" dialog so the user picks the path.
///
/// [savePhoto] returns a [PhotoSaveResult] so the caller can tell a successful
/// save (optionally with a user-visible path) from a cancellation (the desktop
/// dialog was dismissed) and from a real failure.
library;

export 'photo_save_result.dart';
export 'photo_download_stub.dart'
    if (dart.library.io) 'photo_download_io.dart'
    if (dart.library.js_interop) 'photo_download_web.dart';
