# Homebrew cask template. 1.8.50+73, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.50+73/knitcalc-macos-1.8.50+73.zip and 11d0d746d43f7af41521aa5645854140dc050947fbef962d5ef279cb94ad4dda are filled in by
# the `publish` job of .github/workflows/publish.yml, which renders the result
# to Casks/knitcalc.rb on main — the repo itself doubles as the tap, exactly
# like the Scoop bucket. Version keeps the full +build metadata (the macOS zip
# filename and release URL do too); Homebrew cask versions are free-form.
cask "knitcalc" do
  version "1.8.50+73"
  sha256 "11d0d746d43f7af41521aa5645854140dc050947fbef962d5ef279cb94ad4dda"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.50+73/knitcalc-macos-1.8.50+73.zip",
      verified: "github.com/dmezhnov/knitcalc/"
  name "KnitCalc"
  desc "KnitCalc is a knitting calculator"
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
