# Generated from packaging/metadata/metadata.yaml by tool/packaging_metadata.dart.
# Edit that file and run `mise metadata`; changes here are overwritten.
#
# Homebrew cask template. 1.9.2+106, https://github.com/dmezhnov/knitcalc/releases/download/v1.9.2+106/knitcalc-macos-1.9.2+106.zip and 455120ea6bcb0e24315b17a8cfcb26af3f27c811790b899d8e170f5010c18fc2 are filled in
# by the `publish` job of .github/workflows/publish.yml, which renders the
# result to Casks/knitcalc.rb on main — the repo itself doubles as the
# tap, exactly like the Scoop bucket. Version keeps the full +build metadata
# (the macOS zip filename and release URL do too); cask versions are free-form.
cask "knitcalc" do
  version "1.9.2+106"
  sha256 "455120ea6bcb0e24315b17a8cfcb26af3f27c811790b899d8e170f5010c18fc2"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.9.2+106/knitcalc-macos-1.9.2+106.zip",
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
