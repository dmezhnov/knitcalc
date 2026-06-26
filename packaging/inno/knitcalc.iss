; Inno Setup script for the KnitCalc Windows installer.
;
; Compiled by the release CI: `iscc /DAppVersion=<full> packaging/inno/knitcalc.iss`
; (full = marketing+build version, e.g. 1.8.64+87). It wraps the Flutter Windows
; bundle (build/windows/x64/runner/Release/*) into a per-user installer so the
; app's DLLs sit next to knitcalc.exe and resolve — unlike the old winget
; portable package, whose symlink alias broke the DLL search path.
;
; Distribution + self-update (see lib/update/impl/windows/windows_update_service_io.dart):
;   - Installs per-user under {localappdata}\Programs\KnitCalc — no admin/UAC, so
;     the in-app self-update can run the installer silently.
;   - winget runs this same installer (InstallerType: inno, Scope: user).
;   - Self-update downloads the new setup.exe and runs it with
;     `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RELAUNCH`: the Restart Manager
;     closes the running instance, files are swapped in place, and the /RELAUNCH
;     flag relaunches the app afterwards. The installer also refreshes the
;     Add/Remove Programs version, so winget stays consistent.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppFull AppVersion
; VersionInfoVersion must be numeric, so drop any "+build" metadata.
#define PlusPos Pos("+", AppFull)
#if PlusPos > 0
  #define AppNumeric Copy(AppFull, 1, PlusPos - 1)
#else
  #define AppNumeric AppFull
#endif

[Setup]
; Stable AppId across versions → upgrades replace in place; winget matches the
; Add/Remove Programs entry "{<AppId>}_is1".
AppId={{3E2280E5-0275-4912-A2FF-CB4B7F32C007}
AppName=KnitCalc
AppVersion={#AppFull}
AppVerName=KnitCalc {#AppFull}
VersionInfoVersion={#AppNumeric}
AppPublisher=Dmitry Mezhnov
AppPublisherURL=https://github.com/dmezhnov/knitcalc
AppSupportURL=https://github.com/dmezhnov/knitcalc/issues
; Per-user install: {autopf} resolves to {localappdata}\Programs without admin.
PrivilegesRequired=lowest
DefaultDirName={autopf}\KnitCalc
DefaultGroupName=KnitCalc
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=knitcalc-setup-x64-{#AppFull}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\knitcalc.exe
UninstallDisplayName=KnitCalc
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Let the Restart Manager close a running instance during an in-place update;
; we relaunch ourselves via the /RELAUNCH [Run] entry, so don't auto-restart.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\KnitCalc"; Filename: "{app}\knitcalc.exe"
Name: "{group}\Uninstall KnitCalc"; Filename: "{uninstallexe}"

[Run]
; Interactive install: offer a "launch now" checkbox (hidden on silent installs).
Filename: "{app}\knitcalc.exe"; Description: "{cm:LaunchProgram,KnitCalc}"; \
    Flags: nowait postinstall skipifsilent
; Self-update (silent + /RELAUNCH): relaunch the app once the swap is done.
Filename: "{app}\knitcalc.exe"; Flags: nowait; \
    Check: WizardSilent and RelaunchRequested

[Code]
// True when the installer was invoked with /RELAUNCH (set by the in-app
// self-updater) so the silent run relaunches KnitCalc after installing.
function RelaunchRequested: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/RELAUNCH') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;
