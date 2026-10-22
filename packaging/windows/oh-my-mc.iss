// Inno Setup script for the Windows build.
//
// The output is a single `oh-my-mc-<version>-windows-x64-setup.exe`: double-click,
// pick a directory, done. Anything less than an installer (a zip of the release
// folder) is not "install right away" - it leaves the user to find the exe inside
// a folder of DLLs and to make their own shortcut.
//
// Built by .github/workflows/release-windows.yml, which passes the version:
//   ISCC.exe /DMyAppVersion=1.4.0 packaging\windows\oh-my-mc.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif

#define MyAppName "oh my mc"
#define MyAppPublisher "Vedaru"
#define MyAppUrl "https://git.vedaru.cn/Vedaru/oh-my-mc"
#define MyAppExeName "oh_my_mc.exe"

[Setup]
; A stable AppId is what makes an upgrade replace the previous install instead of
; sitting next to it. Never change it.
AppId={{7C2B9E54-4E5A-4C8E-9E2B-0F5D6A1C3B77}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppUrl}
AppSupportURL={#MyAppUrl}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; The launcher writes to %LOCALAPPDATA%; nothing needs admin, so the installer
; does not ask for it either.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=oh-my-mc-{#MyAppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release folder: the exe needs its DLLs and the data\ tree next
; to it, so the installer ships the folder rather than pretending the exe stands
; alone.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The launcher's own data (instances, downloaded JVMs, assets) lives outside the
; install directory on purpose: uninstalling the launcher must not delete the
; user's Minecraft. Nothing to clean up here beyond what Inno tracks.
