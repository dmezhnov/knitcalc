# Homebrew cask template. 1.8.38+61, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.38+61/knitcalc-macos-1.8.38+61.zip and ae385310a6bcd14f64a63679124b1684dae24cbbb8b75a1027c20a5b3345e13e are filled in by
# the `publish` job of .github/workflows/publish.yml, which renders the result
# to Casks/knitcalc.rb on main — the repo itself doubles as the tap, exactly
# like the Scoop bucket. Version keeps the full +build metadata (the macOS zip
# filename and release URL do too); Homebrew cask versions are free-form.
cask "knitcalc" do
  version "1.8.38+61"
  sha256 "ae385310a6bcd14f64a63679124b1684dae24cbbb8b75a1027c20a5b3345e13e"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.38+61/knitcalc-macos-1.8.38+61.zip",
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
