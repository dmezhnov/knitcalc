/// Web photo save: trigger a normal browser download via an object-URL anchor.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:knitcalc/photo_save_result.dart';
import 'package:web/web.dart' as web;

Future<PhotoSaveResult> savePhoto(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/jpeg'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  // Append so the click reliably dispatches across browsers, then clean up.
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return const PhotoSaveResult(PhotoSaveStatus.saved);
}
