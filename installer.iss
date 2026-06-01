; Inno Setup script for Yomira (Windows .exe installer).
; Build first:  flutter build windows --release
; Then compile:  & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

#define AppName "Yomira"
#define AppVersion "1.2.1"
#define AppPublisher "Tickrate"
#define AppExe "tappreader.exe"

[Setup]
AppId={{B9E2C7A4-1F3D-4E5A-9C8B-YOMIRA000001}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://tickrate.fr
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=installer
OutputBaseFilename=Yomira-Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Ship the whole release folder, minus the msix/cert artifacts.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Excludes: "*.msix,*.pfx,*.cer"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
