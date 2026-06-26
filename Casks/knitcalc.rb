# Homebrew cask template. 1.8.64+87, https://github.com/dmezhnov/knitcalc/releases/download/v1.8.64+87/knitcalc-macos-1.8.64+87.zip and d76bf20a3f64e30716a95dfcf7f52aa427f029aafca6e9f9ee5a5ff812b839b2 are filled in by
# the `publish` job of .github/workflows/publish.yml, which renders the result
# to Casks/knitcalc.rb on main — the repo itself doubles as the tap, exactly
# like the Scoop bucket. Version keeps the full +build metadata (the macOS zip
# filename and release URL do too); Homebrew cask versions are free-form.
cask "knitcalc" do
  version "1.8.64+87"
  sha256 "d76bf20a3f64e30716a95dfcf7f52aa427f029aafca6e9f9ee5a5ff812b839b2"

  url "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.64+87/knitcalc-macos-1.8.64+87.zip",
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
