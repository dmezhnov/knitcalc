import 'package:knitcalc/l10n/app_localizations.dart';

/// Formats a byte count as a short human-readable size.
///
/// Uses binary units (1 KiB = 1024 B) but labels them with [base] for bytes and
/// [multiples] (KB/MB/GB/TB) for larger sizes, supplied by the caller so the
/// units follow the active locale. Values of 10 and above are shown without a
/// fractional digit ("12 MB"), smaller ones keep one ("3.4 MB").
String formatBytesWithUnits(
  int bytes, {
  required String base,
  required List<String> multiples,
}) {
  if (bytes < 1024) {
    return '$bytes $base';
  }

  var value = bytes / 1024;
  var unit = 0;

  while (value >= 1024 && unit < multiples.length - 1) {
    value /= 1024;
    unit++;
  }

  final text = value >= 10
      ? value.round().toString()
      : value.toStringAsFixed(1);

  return '$text ${multiples[unit]}';
}

/// Locale-aware byte formatting for update UI widgets.
extension ByteFormatL10n on AppLocalizations {
  /// Formats [bytes] using this locale's byte-unit abbreviations.
  String formatBytes(int bytes) => formatBytesWithUnits(
    bytes,
    base: byteUnitB,
    multiples: [byteUnitKB, byteUnitMB, byteUnitGB, byteUnitTB],
  );
}
