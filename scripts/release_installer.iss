#ifndef ReleaseVersion
  #define ReleaseVersion "1.2.10"
#endif
#ifndef SourceDir
  #error SourceDir must point to the complete Flutter Windows release directory
#endif

[Setup]
AppId={{F0091D44-0662-41B1-9EED-B8ACE4EC4977}
AppName=gew_erp
AppVersion={#ReleaseVersion}
AppPublisher=General Engineering Works
DefaultDirName={autopf}\gew_erp
UninstallDisplayIcon={app}\gew_erp.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
OutputBaseFilename=gewerp_setup
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\gew_erp"; Filename: "{app}\gew_erp.exe"
Name: "{autodesktop}\gew_erp"; Filename: "{app}\gew_erp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gew_erp.exe"; Description: "{cm:LaunchProgram,gew_erp}"; Flags: nowait postinstall skipifsilent
