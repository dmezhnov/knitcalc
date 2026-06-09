/// Native (`dart:io`) photo save: Android/iOS → the device gallery (via the
/// native method channel); desktop → a "Save As" dialog the user controls.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:knitcalc/photo_save_result.dart';

/// Shared native channel (also used by the updater and legacy cleanup).
const MethodChannel _channel = MethodChannel('knitcalc/android_update');

Future<PhotoSaveResult> savePhoto(Uint8List bytes, String fileName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    // Mobile can't write to a public folder freely, so hand the bytes to the
    // native side, which saves them to the gallery (MediaStore / Photos).
    final saved = await _channel.invokeMethod<bool>('saveImageToGallery', {
      'bytes': bytes,
      'name': fileName,
    });
    return (saved ?? false)
        ? const PhotoSaveResult(PhotoSaveStatus.saved)
        : const PhotoSaveResult(PhotoSaveStatus.failed);
  }

  // Desktop: let the user choose where to save. This is also the only
  // sandbox-friendly path on macOS (the OS grants write access to the picked
  // file via powerbox), where writing to a fixed folder is blocked.
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JPEG', extensions: ['jpg', 'jpeg']),
    ],
  );
  if (location == null) {
    return const PhotoSaveResult(PhotoSaveStatus.cancelled);
  }

  final file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: fileName);
  await file.saveTo(location.path);
  return PhotoSaveResult(PhotoSaveStatus.saved, location.path);
}
