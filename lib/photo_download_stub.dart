/// Fallback used when neither `dart:io` nor `dart:js_interop` is available.
/// No platform to save to, so report failure.
library;

import 'dart:typed_data';

import 'package:knitcalc/photo_save_result.dart';

Future<PhotoSaveResult> savePhoto(Uint8List bytes, String fileName) async =>
    const PhotoSaveResult(PhotoSaveStatus.failed);
