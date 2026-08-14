# Generated from packaging/metadata/metadata.yaml by tool/packaging_metadata.dart.
# Edit that file and run `mise metadata`; changes here are overwritten.
#
# Homebrew cask template. 1.8.76+99, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.76+99/knitcalc-macos-1.8.76+99.zip and 8fd5d0e9e4cf56029554b8e89f9a4f8fb786ec02dc2b14c007ce264077b42490 are filled in
# by the `publish` job of .github/workflows/publish.yml, which renders the
# result to Casks/knitcalc.rb on main — the repo itself doubles as the
# tap, exactly like the Scoop bucket. Version keeps the full +build metadata
# (the macOS zip filename and release URL do too); cask versions are free-form.
cask "knitcalc" do
  version "1.8.76+99"
  sha256 "8fd5d0e9e4cf56029554b8e89f9a4f8fb786ec02dc2b14c007ce264077b42490"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.76+99/knitcalc-macos-1.8.76+99.zip",
      verified: "github.com/dmezhnov/knitcalc/"
  name "KnitCalc"
  desc "Knitting calculator: gauge conversion, stitch counts, yarn estimation"
  homepage "https://github.com/dmezhnov/knitcalc"

  app "knitcalc.app"

  # The macOS build is unsigned and unnotarized, so install with
  # `--no-quarantine` (otherwise Gatekeeper blocks first launch).
  zap trash: [
    "~/Library/Application Support/io.github.dmezhnov.knitcalc",
    "~/Library/Preferences/io.github.dmezhnov.knitcalc.plist",
    "~/Library/Saved Application State/io.github.dmezhnov.knitcalc.savedState",
  ]
end
