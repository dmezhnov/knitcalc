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
; The Add/Remove Programs DisplayVersion (AppVersion) MUST equal the bare semver
; that the winget manifest carries (Dmezhnov.KnitCalc.yaml's PackageVersion —
; winget rejects "+build" metadata). winget correlates the install by ProductCode
; and reads this DisplayVersion as the installed version; if it carried the full
; "1.8.x+build" it would never match the manifest's "1.8.x", so `winget upgrade`
; (and the in-app winget-channel probe) would forever report a phantom upgrade and
; reinstall the same version on every launch. So use the build-stripped AppNumeric.
AppVersion={#AppNumeric}
AppVerName=KnitCalc {#AppNumeric}
VersionInfoVersion={#AppNumeric}
AppPublisher=Dmitry Mezhnov
AppPublisherURL=https://github.com/dmezhnov/knitcalc
AppSupportURL=https://github.com/dmezhnov/knitcalc/issues
; Per-user install: {autopf} resolves to {localappdata}\Programs without admin.
PrivilegesRequired=lowest
DefaultDirName={autopf}\KnitCalc
DisableDirPage=yes
DisableProgramGroupPage=yes
; The "Add to PATH" task edits HKCU\Environment; broadcast the change so open
; shells pick up the new PATH without a re-login.
ChangesEnvironment=yes
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

[Tasks]
; Put {app} on the user's PATH so `knitcalc` works from a terminal (the old
; winget portable alias used to provide this). Checked by default, so a silent
; winget/self-update install applies it too. Unlike the portable symlink, this
; points at the real {app}\knitcalc.exe, whose own directory is first in the DLL
; search path — the bundled DLLs resolve.
Name: "modifypath"; Description: "{cm:AddToPath}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; A single shortcut directly under the Start menu Programs root (not a one-app
; subfolder, which Windows 11's app list hides poorly). Uninstall is via
; Settings / Add-Remove Programs.
Name: "{autoprograms}\KnitCalc"; Filename: "{app}\knitcalc.exe"

[UninstallDelete]
; The install-source marker is written by [Code], so the uninstaller doesn't
; track it automatically.
Type: files; Name: "{app}\install_source"

[CustomMessages]
english.AddToPath=Add KnitCalc to PATH (run `knitcalc` from a terminal)
russian.AddToPath=Добавить KnitCalc в PATH (запуск `knitcalc` из терминала)
english.RemoveDataPrompt=Also delete your saved KnitCalc projects? You will be signed out of your account either way.
russian.RemoveDataPrompt=Удалить также сохранённые проекты KnitCalc? Из аккаунта вы выйдете в любом случае.

[Run]
; Interactive install: offer a "launch now" checkbox (hidden on silent installs).
Filename: "{app}\knitcalc.exe"; Description: "{cm:LaunchProgram,KnitCalc}"; \
    Flags: nowait postinstall skipifsilent
; Self-update (silent + /RELAUNCH): relaunch the app once the swap is done.
Filename: "{app}\knitcalc.exe"; Flags: nowait; \
    Check: WizardSilent and RelaunchRequested

[Code]
const
  EnvironmentKey = 'Environment';

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

// Append Path to the per-user PATH (HKCU\Environment), skipping if already
// present. Standard Inno pattern; ChangesEnvironment=yes broadcasts the update.
procedure EnvAddPath(Path: string);
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    Paths := '';
  if Pos(';' + Uppercase(Path) + ';', ';' + Uppercase(Paths) + ';') > 0 then
    Exit;
  if Paths = '' then
    Paths := Path
  else
    Paths := Paths + ';' + Path;
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths);
end;

// Remove Path from the per-user PATH, if present (used on uninstall).
procedure EnvRemovePath(Path: string);
var
  Paths: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    Exit;
  P := Pos(';' + Uppercase(Path) + ';', ';' + Uppercase(Paths) + ';');
  if P = 0 then
    Exit;
  Delete(Paths, P - 1, Length(Path) + 1);
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths);
end;

// Record how this copy was installed so the app picks the right update channel
// (see lib/update/channel.dart): a silent run without /RELAUNCH is winget; an
// interactive run is a direct download. A self-update (/RELAUNCH) re-runs over an
// existing install, so it keeps the original marker rather than overwriting it.
procedure WriteInstallSource;
var
  Source: string;
begin
  if RelaunchRequested then
    Exit;
  if WizardSilent then
    Source := 'winget'
  else
    Source := 'manual';
  SaveStringToFile(ExpandConstant('{app}\install_source'), Source, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('modifypath') then
      EnvAddPath(ExpandConstant('{app}'));
    WriteInstallSource;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: string;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;

  EnvRemovePath(ExpandConstant('{app}'));

  // Per-user data lives under %APPDATA%\<CompanyName>\<ProductName> — the dir
  // path_provider's getApplicationSupportDirectory returns, where both
  // shared_preferences (saved projects) and our auth_session.json sit. The names
  // come from windows/runner/Runner.rc (the default template com.example/knitcalc).
  DataDir := ExpandConstant('{userappdata}\com.example\knitcalc');

  // Always sign out. The session is kept in its own file (see
  // lib/firebase/session_store_io.dart), so deleting just it logs the user out
  // while leaving saved projects untouched.
  DeleteFile(DataDir + '\auth_session.json');

  // Offer to also wipe the saved projects. On a silent uninstall (e.g.
  // `winget uninstall`) MsgBox is suppressed and returns the default button —
  // MB_DEFBUTTON2 = "No" — so projects are kept while the sign-out above still ran.
  if MsgBox(CustomMessage('RemoveDataPrompt'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    DelTree(DataDir, True, True, True);
end;
