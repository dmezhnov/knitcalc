# Homebrew cask template. 1.8.65+88, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.65+88/knitcalc-macos-1.8.65+88.zip and 5c874e600fc2f831eab0ce6d84d7b6dc8dcafb68174188e27521220bafd12e32 are filled in by
# the `publish` job of .github/workflows/publish.yml, which renders the result
# to Casks/knitcalc.rb on main — the repo itself doubles as the tap, exactly
# like the Scoop bucket. Version keeps the full +build metadata (the macOS zip
# filename and release URL do too); Homebrew cask versions are free-form.
cask "knitcalc" do
  version "1.8.65+88"
  sha256 "5c874e600fc2f831eab0ce6d84d7b6dc8dcafb68174188e27521220bafd12e32"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.65+88/knitcalc-macos-1.8.65+88.zip",
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
