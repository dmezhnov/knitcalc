import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:knitcalc/storage/photo_codec.dart';

/// Encodes a solid [width]x[height] image to PNG bytes for use as picker input.
Uint8List pngBytes(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));

  return img.encodePng(image);
}

void main() {
  test('downscales an oversized photo to the bounded dimension', () {
    final encoded = encodePhoto(pngBytes(2000, 1500));

    expect(encoded, isNotNull);

    final decoded = img.decodeImage(decodePhoto(encoded!))!;
    expect(decoded.width, kPhotoMaxDimension);
    expect(decoded.height, (1500 * kPhotoMaxDimension / 2000).round());
  });

  test('leaves a small photo at its original size', () {
    final encoded = encodePhoto(pngBytes(300, 200));

    final decoded = img.decodeImage(decodePhoto(encoded!))!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('re-encodes to JPEG', () {
    final encoded = encodePhoto(pngBytes(100, 100));

    // findDecoderForData returns the JpegDecoder for JPEG payloads.
    expect(
      img.findDecoderForData(decodePhoto(encoded!)),
      isA<img.JpegDecoder>(),
    );
  });

  test('returns null for non-image bytes', () {
    expect(encodePhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
