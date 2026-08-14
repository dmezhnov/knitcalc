# Generated from packaging/metadata/metadata.yaml by tool/packaging_metadata.dart.
# Edit that file and run `mise metadata`; changes here are overwritten.
#
# Homebrew cask template. 1.8.79+102, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.79+102/knitcalc-macos-1.8.79+102.zip and 004c7c2d91db8bb2f216c7890e52e65e5b7dfa1a1d58e0d86a6fe85fd275494e are filled in
# by the `publish` job of .github/workflows/publish.yml, which renders the
# result to Casks/knitcalc.rb on main — the repo itself doubles as the
# tap, exactly like the Scoop bucket. Version keeps the full +build metadata
# (the macOS zip filename and release URL do too); cask versions are free-form.
cask "knitcalc" do
  version "1.8.79+102"
  sha256 "004c7c2d91db8bb2f216c7890e52e65e5b7dfa1a1d58e0d86a6fe85fd275494e"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.79+102/knitcalc-macos-1.8.79+102.zip",
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
