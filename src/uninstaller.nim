# Minimal uninstaller for TopHat-ShooterOS
# Compile with:
#   nim c -d:release -d:danger --opt:size --mm:arc --app:gui --passL:"-s" -d:noSignalHandler --out:uninstaller.exe uninstaller.nim
# For another application, also pass -d:AppDisplayName=... and -d:AppRegKey=...

when not defined(windows):
  {.error: "This uninstaller targets Windows only.".}

import std/[os, osproc, strutils, widestrs]

proc MessageBoxW(hWnd: int; text, caption: WideCString; uType: cuint): cint
  {.stdcall, importc, dynlib: "user32".}

proc SendMessageTimeoutW(hWnd: int; msg: cuint; wParam: uint;
                         lParam: WideCString; fuFlags, uTimeout: cuint;
                         lpdwResult: ptr uint): int
  {.stdcall, importc, dynlib: "user32".}

proc RegOpenKeyExW(hKey: int; lpSubKey: WideCString; ulOptions: culong;
                   samDesired: culong; phkResult: ptr int): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegQueryValueExW(hKey: int; lpValueName: WideCString;
                      lpReserved: ptr culong; lpType: ptr culong;
                      lpData: pointer; lpcbData: ptr culong): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegSetValueExW(hKey: int; lpValueName: WideCString; reserved: culong;
                    dwType: culong; lpData: pointer; cbData: culong): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegDeleteKeyExW(hKey: int; lpSubKey: WideCString; samDesired: culong;
                     reserved: culong): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RegCloseKey(hKey: int): clong
  {.stdcall, importc, dynlib: "advapi32".}

proc RemoveDirectoryW(lpPathName: WideCString): int32
  {.stdcall, importc, dynlib: "kernel32".}

proc OpenProcess(dwDesiredAccess: uint32; bInheritHandle: int32;
                 dwProcessId: uint32): int
  {.stdcall, importc, dynlib: "kernel32".}

proc WaitForSingleObject(hHandle: int; dwMilliseconds: uint32): uint32
  {.stdcall, importc, dynlib: "kernel32".}

proc CloseHandle(hObject: int): int32
  {.stdcall, importc, dynlib: "kernel32".}

proc MoveFileExW(lpExistingFileName, lpNewFileName: WideCString;
                 dwFlags: uint32): int32
  {.stdcall, importc, dynlib: "kernel32".}

proc IsUserAnAdmin(): int32
  {.stdcall, importc, dynlib: "shell32".}

proc ShellExecuteW(hwnd: int; lpOperation, lpFile, lpParameters,
                   lpDirectory: WideCString; nShowCmd: cint): int
  {.stdcall, importc, dynlib: "shell32".}

const
  MB_OK            = 0'u32
  MB_YESNO         = 4'u32
  MB_ICONERROR     = 0x10'u32
  MB_ICONQUESTION  = 0x20'u32
  IDYES            = 6
  SW_SHOWNORMAL    = 1
  SE_ERR_ACCESSDENIED = 5 # also returned when the user declines the UAC prompt
  HWND_BROADCAST   = 0xFFFF
  WM_SETTINGCHANGE = 0x1A'u32
  SMTO_ABORTIFHUNG = 2'u32
  HKLM             = 0x80000002
  KEY_READ         = 0x20019'u32
  KEY_SET_VALUE    = 0x2'u32
  # The installer runs in 64-bit mode on 64-bit Windows, so its HKLM entries
  # live in the 64-bit registry view; ignored on 32-bit Windows.
  KEY_WOW64_64KEY  = 0x100'u32
  REG_EXPAND_SZ    = 2'u32
  SYNCHRONIZE      = 0x100000'u32
  MOVEFILE_DELAY_UNTIL_REBOOT = 4'u32
  CleanupFlag      = "--cleanup"
  EnvRegKey        = r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
  AppDisplayName {.strdefine.} = "TopHat-ShooterOS"
  AppRegKey {.strdefine.} = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\TopHatShooterOS"

proc showMessage(text: string; flags: uint32): cint =
  MessageBoxW(0, newWideCString(text), newWideCString("Uninstall " & AppDisplayName),
              flags)

proc regReadString(key: int; valueName: string): string =
  ## Reads a string value without expanding it; "" if it does not exist.
  let name = newWideCString(valueName)
  var size: culong = 0
  if RegQueryValueExW(key, name, nil, nil, nil, addr size) != 0 or size == 0:
    return ""
  # one extra char, as the stored data is not guaranteed to be terminated
  var buf = newSeq[Utf16Char](size.int div sizeof(Utf16Char) + 1)
  if RegQueryValueExW(key, name, nil, nil, addr buf[0], addr size) != 0:
    return ""
  result = $cast[WideCString](addr buf[0])

proc regWriteExpandString(key: int; valueName, value: string): bool =
  let data = newWideCString(value)
  let bytes = (data.len + 1) * sizeof(Utf16Char)
  RegSetValueExW(key, newWideCString(valueName), 0, REG_EXPAND_SZ,
                 cast[pointer](toWideCString(data)), bytes.culong) == 0

proc removeFromPath(entries: string) =
  ## Removes the directories the installer added from the system PATH.
  if entries.len == 0: return
  var remove: seq[string]
  for e in entries.split(';'):
    if e.len > 0: remove.add(e.toLowerAscii)
  var env: int
  if RegOpenKeyExW(HKLM, newWideCString(EnvRegKey), 0,
                   KEY_READ or KEY_SET_VALUE, addr env) != 0:
    return
  let oldPath = regReadString(env, "Path")
  var kept: seq[string]
  for p in oldPath.split(';'):
    if p.toLowerAscii notin remove: kept.add(p)
  let newPath = kept.join(";")
  let changed = newPath != oldPath and regWriteExpandString(env, "Path", newPath)
  discard RegCloseKey(env)
  if changed:
    var res: uint
    discard SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                                newWideCString("Environment"),
                                SMTO_ABORTIFHUNG, 5000, addr res)

proc cleanup(installDir: string; pid: int) =
  ## Runs from a copy in %TEMP%: waits for the uninstaller (process `pid`) to
  ## exit, deletes the installation folder and then, on the next reboot, itself.
  let h = OpenProcess(SYNCHRONIZE, 0, pid.uint32)
  if h != 0:
    discard WaitForSingleObject(h, 30_000)
    discard CloseHandle(h)
  for _ in 1..20:
    try:
      removeDir(installDir)
      break
    except OSError:
      sleep(500)
  discard MoveFileExW(newWideCString(getAppFilename()), nil,
                      MOVEFILE_DELAY_UNTIL_REBOOT)

proc removeShortcut(path: string) =
  if path.len > 0:
    try: removeFile(path) except OSError: discard

proc main() =
  # The installer is per-machine: removing the files from Program Files and
  # the HKLM entries needs administrator rights, so restart elevated.
  if IsUserAnAdmin() == 0:
    let r = ShellExecuteW(0, newWideCString("runas"),
                          newWideCString(getAppFilename()), nil, nil,
                          SW_SHOWNORMAL)
    if r <= 32 and r != SE_ERR_ACCESSDENIED:
      discard showMessage("Administrator rights are required to uninstall " &
                          AppDisplayName & ".", MB_OK or MB_ICONERROR)
    return

  var installDir = getAppDir()

  # Read everything we need from the registry before we delete the key
  var hKey: int
  var installLocation, desktopShortcut, startMenuDir, startMenuShortcut,
      docShortcuts, pathEntries: string
  if RegOpenKeyExW(HKLM, newWideCString(AppRegKey), 0,
                   KEY_READ or KEY_WOW64_64KEY, addr hKey) == 0:
    installLocation   = regReadString(hKey, "InstallLocation")
    desktopShortcut   = regReadString(hKey, "DesktopShortcut")
    startMenuDir      = regReadString(hKey, "StartMenuDir")
    startMenuShortcut = regReadString(hKey, "StartMenuShortcut")
    docShortcuts      = regReadString(hKey, "DocShortcuts")
    pathEntries       = regReadString(hKey, "PathEntries")
    discard RegCloseKey(hKey)

  # The whole folder this exe lives in gets deleted, so refuse to run from
  # anywhere but the installation folder (e.g. a copy in Downloads).
  if (installLocation.len > 0 and cmpPaths(installLocation, installDir) != 0) or
      isRootDir(installDir):
    discard showMessage("This uninstaller is not inside the " & AppDisplayName &
                        " installation folder" &
                        (if installLocation.len > 0: " (" & installLocation & ")"
                         else: "") &
                        ", so nothing was removed.", MB_OK or MB_ICONERROR)
    return

  let answer = showMessage(
    "Are you sure you want to uninstall " & AppDisplayName & "?\n\n" &
    "All game files in the installation folder will be removed.",
    MB_YESNO or MB_ICONQUESTION)

  if answer != IDYES: return

  # Remove only the shortcuts the installer created. Installations made by
  # older installers have no StartMenuDir value, so derive it from the shortcut.
  if startMenuDir.len == 0 and startMenuShortcut.len > 0:
    startMenuDir = parentDir(startMenuShortcut)
  removeShortcut(desktopShortcut)
  removeShortcut(startMenuShortcut)
  for s in docShortcuts.split(';'): removeShortcut(s)
  # The user may have picked an existing Start Menu folder during setup, so
  # it is only removed when nothing else is left in it.
  if startMenuDir.len > 0:
    discard RemoveDirectoryW(newWideCString(startMenuDir))

  removeFromPath(pathEntries)

  # Remove Add/Remove Programs registry entry
  discard RegDeleteKeyExW(HKLM, newWideCString(AppRegKey), KEY_WOW64_64KEY, 0)

  # This exe is still running and locks the folder, so a copy outside of it
  # removes the folder once we have exited. Its working directory must be
  # outside the folder too, or the copy itself would keep it from being deleted.
  let pid = getCurrentProcessId()
  let cleanupExe = getTempDir() / ("uninstall_cleanup_" & $pid & ".exe")
  try:
    copyFile(getAppFilename(), cleanupExe)
    let p = startProcess(cleanupExe, workingDir = getTempDir(),
                         args = [CleanupFlag, installDir, $pid],
                         options = {poDaemon})
    p.close()
  except OSError:
    discard showMessage("The shortcuts and registry entries were removed, but " &
                        "the installation folder could not be deleted:\n\n" &
                        installDir & "\n\nPlease delete it manually.",
                        MB_OK or MB_ICONERROR)

if paramCount() == 3 and paramStr(1) == CleanupFlag:
  cleanup(paramStr(2), parseInt(paramStr(3)))
else:
  main()
