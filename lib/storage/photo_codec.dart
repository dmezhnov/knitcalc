/// Compresses picked photos for inline storage.
///
/// Photos are stored base64-encoded inside the project JSON (so the same record
/// works on every platform, including web localStorage). To keep that small,
/// each photo is downscaled to a bounded dimension and re-encoded as JPEG before
/// encoding. Decoding is just base64 → bytes, ready for [Image.memory].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side, in pixels, a stored photo is scaled down to.
const int kPhotoMaxDimension = 1024;

/// JPEG quality (0–100) used when re-encoding a stored photo.
const int kPhotoJpegQuality = 80;

/// Decodes [bytes] (any format the `image` package understands), downscales it
/// so its longest side is at most [kPhotoMaxDimension], re-encodes it as JPEG,
/// and returns the base64 string to store. Returns `null` when the bytes are not
/// a decodable image.
String? encodePhoto(Uint8List bytes) {
  // decodeImage returns null for unrecognised data but can also throw on
  // truncated/garbage bytes, so treat both as "not an image".
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) {
    return null;
  }

  final longestSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;

  final image = longestSide > kPhotoMaxDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? kPhotoMaxDimension : null,
          height: decoded.height > decoded.width ? kPhotoMaxDimension : null,
        )
      : decoded;

  final jpeg = img.encodeJpg(image, quality: kPhotoJpegQuality);

  return base64Encode(jpeg);
}

/// Decodes a stored photo string back into raw JPEG bytes for display.
Uint8List decodePhoto(String encoded) => base64Decode(encoded);
