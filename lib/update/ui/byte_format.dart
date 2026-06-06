/// Formats a byte count as a short human-readable size for the update UI.
///
/// Uses binary units (1 KiB = 1024 B) but labels them with the familiar Russian
/// abbreviations (Б/КБ/МБ/ГБ). Values of 10 and above are shown without a
/// fractional digit ("12 МБ"), smaller ones keep one ("3.4 МБ").
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes Б';
  }

  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes / 1024;
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  final text = value >= 10
      ? value.round().toString()
      : value.toStringAsFixed(1);

  return '$text ${units[unit]}';
}
