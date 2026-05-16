# KnitCalc

KnitCalc is a small Flutter calculator for rectangular scarf knitting. It helps
convert a sample swatch into target stitch, row, and yarn-length estimates.

## Features

- Product type selector with a rectangular scarf preset.
- Inputs for stitch count, row count, sample dimensions, target dimensions, and
  sample yarn length.
- Live output calculations for:
  - stitches per centimeter
  - rows per centimeter
  - target stitch count
  - target row count
  - target yarn length
- Nix flake for a reproducible Flutter and Android SDK development shell on
  NixOS.

## Requirements

- Flutter
- Android SDK for APK builds
- Nix with flakes enabled, if using the included Nix shell

## Development

Enter the Nix development shell:

```bash
nix develop path:$PWD
```

Run the app:

```bash
flutter run
```

Analyze the project:

```bash
flutter analyze
```

## Build APK

Inside the development shell, build a release APK:

```bash
flutter build apk
```

The APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
