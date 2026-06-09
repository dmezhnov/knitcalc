# {{URL}} / {{SHA256}} are filled in by the publish workflow (pointing at the
# knitcalc-windows-x64-<version>.zip GitHub release asset) before `choco pack`.
$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    PackageName    = 'knitcalc'
    UnzipLocation  = $toolsDir
    Url64bit       = '{{URL}}'
    Checksum64     = '{{SHA256}}'
    ChecksumType64 = 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

# Shimgen shims every exe under tools/ after this script: mark the app GUI so
# its shim doesn't hold a console window, and keep the bundled self-updater
# helper out of PATH entirely.
New-Item -Path "$toolsDir\knitcalc.exe.gui" -ItemType File -Force | Out-Null
New-Item -Path "$toolsDir\knitcalc_updater.exe.ignore" -ItemType File -Force | Out-Null
