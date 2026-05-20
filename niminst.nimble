# Package

version       = "1.0.0"
author        = "Paycei"
description   = "Custom niminst package for TopHat-Shooteros"
license       = "MIT"
srcDir        = "src"
bin           = @["niminst"]

# Dependencies

requires "nim >= 2.2.10"

task release, "Build Niminst for release":
  exec "nim c -d:release --out:niminst.exe src/niminst.nim"

task uninstaller, "Build the uninstaller":
  exec "nim c -d:release -d:danger --opt:size --mm:arc --app:gui --passL:\"-s\" -d:noSignalHandler --out:uninstaller.exe src/uninstaller.nim"
