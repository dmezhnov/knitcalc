{
  description = "Flutter Android dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      androidComposition = pkgs.androidenv.composeAndroidPackages {
        platformVersions = [
          "35"
          "36"
        ];
        buildToolsVersions = [
          "28.0.3"
          "35.0.0"
          "36.0.0"
        ];
        includeNDK = true;
        ndkVersions = [ "28.2.13676358" ];
        includeCmake = true;
        cmakeVersions = [ "3.22.1" ];
      };

      androidSdk = androidComposition.androidsdk;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.flutter
          pkgs.jdk17
          androidSdk
        ];

        ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
        ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
        JAVA_HOME = "${pkgs.jdk17}";
      };
    };
}
