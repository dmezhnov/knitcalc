# Generated from packaging/metadata/metadata.yaml by tool/packaging_metadata.dart.
# Edit that file and run `mise metadata`; changes here are overwritten.
#
# Homebrew cask template. 1.10.1+109, https://github.com/dmezhnov/knitcalc/releases/download/v1.10.1+109/knitcalc-macos-1.10.1+109.zip and e09bd0b3eba9897bf6cec1f5d3063ba19d910950a91e96b1e81f0be784dfd0bb are filled in
# by the `publish` job of .github/workflows/publish.yml, which renders the
# result to Casks/knitcalc.rb on main — the repo itself doubles as the
# tap, exactly like the Scoop bucket. Version keeps the full +build metadata
# (the macOS zip filename and release URL do too); cask versions are free-form.
cask "knitcalc" do
  version "1.10.1+109"
  sha256 "e09bd0b3eba9897bf6cec1f5d3063ba19d910950a91e96b1e81f0be784dfd0bb"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.10.1+109/knitcalc-macos-1.10.1+109.zip",
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
