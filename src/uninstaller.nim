# Minimal uninstaller for TopHat-ShooterOS
# Compile with:
#   nim c -d:release -d:danger --opt:size --mm:arc --app:gui --passL:"-s" -d:noSignalHandler --out:uninstaller.exe uninstaller.nim

when not defined(windows):
  {.error: "This uninstaller targets Windows only.".}

import std/[os, osproc]

proc MessageBoxA(hWnd: int; text, caption: cstring; uType: cuint): cint
  {.stdcall, importc, dynlib: "user32".}

proc RegOpenKeyExA(hKey: int; lpSubKey: cstring; ulOptions: culong;
                   samDesired: culong; phkResult: ptr int): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegQueryValueExA(hKey: int; lpValueName: cstring; lpReserved: ptr culong;
                      lpType: ptr culong; lpData: pointer;
                      lpcbData: ptr culong): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegCloseKey(hKey: int): clong
  {.stdcall, importc, dynlib: "advapi32".}

const
  MB_YESNO        = 4'u32
  MB_ICONQUESTION = 0x20'u32
  IDYES           = 6
  HKLM            = 0x80000002
  KEY_READ        = 0x20019'u32
  AppDisplayName  = "TopHat-ShooterOS"
  AppRegKey       = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\TopHatShooterOS"

proc regReadString(key: int; valueName: string): string =
  var size: culong = 512
  var buf = newString(512)
  var kind: culong
  if RegQueryValueExA(key, valueName.cstring, nil, addr kind,
                      cast[pointer](addr buf[0]), addr size) == 0:
    buf.setLen(size.int)
    # strip null terminator if present
    while buf.len > 0 and buf[^1] == '\0': buf.setLen(buf.len - 1)
    result = buf
  else:
    result = ""

proc main() =
  let installDir = getAppDir()

  let answer = MessageBoxA(
    0,
    ("Are you sure you want to uninstall " & AppDisplayName & "?\n\n" &
     "All game files in the installation folder will be removed.").cstring,
    ("Uninstall " & AppDisplayName).cstring,
    MB_YESNO or MB_ICONQUESTION)

  if answer != IDYES: return

  # Read shortcut paths from registry before we delete the key
  var hKey: int
  var desktopShortcut, startMenuShortcut, startMenuDir: string
  if RegOpenKeyExA(HKLM, AppRegKey, 0, KEY_READ, addr hKey) == 0:
    desktopShortcut  = regReadString(hKey, "DesktopShortcut")
    startMenuShortcut = regReadString(hKey, "StartMenuShortcut")
    discard RegCloseKey(hKey)

  # Derive Start Menu folder from shortcut path (everything up to last \)
  if startMenuShortcut.len > 0:
    startMenuDir = parentDir(startMenuShortcut)

  # Remove shortcuts
  if desktopShortcut.len > 0:
    try: removeFile(desktopShortcut) except: discard
  if startMenuShortcut.len > 0:
    try: removeFile(startMenuShortcut) except: discard
  if startMenuDir.len > 0:
    try: removeDir(startMenuDir) except: discard

  # Remove Add/Remove Programs registry entry
  discard execCmdEx("reg delete \"HKLM\\" & AppRegKey & "\" /f")

  # Schedule full directory removal
  let tempExe = getTempDir() / "tophat_unins_tmp.exe"
  try: copyFile(getAppFilename(), tempExe)
  except: discard

  let bat = getTempDir() / "tophat_uninstall_cleanup.bat"
  writeFile(bat,
    "@echo off\r\n" &
    ":waitloop\r\n" &
    "tasklist /fi \"imagename eq tophat_unins_tmp.exe\" 2>nul | find /i \"tophat_unins_tmp.exe\" >nul\r\n" &
    "if not errorlevel 1 (\r\n" &
    "  ping -n 2 127.0.0.1 >nul\r\n" &
    "  goto waitloop\r\n" &
    ")\r\n" &
    "del /f /q \"" & tempExe & "\"\r\n" &
    "rmdir /s /q \"" & installDir & "\"\r\n" &
    "(goto) 2>nul & del \"%~f0\"\r\n")

  let p = startProcess("cmd.exe",
    args = ["/c", bat],
    options = {poUsePath, poDaemon})
  p.close()

main()
