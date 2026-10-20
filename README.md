This repository is a "fork" of Niminst, adapted specifically for TopHat-Shooteros to create the installer tailored to that project.

Quick build
-----------
Install dependencies:

```
nimble install -d
```

Requires **Nim 2.2.12** or newer.

**Inno Setup 7** [Download](https://jrsoftware.org/isdl.php/Inno-Setup-Downloads#v7)

Build the `niminst` executable:

```
nimble release
```

Build the `custom uninstaller` executable:

```
nimble uninstaller
```

The generated installer always requires administrator rights (per-machine
install), and the uninstaller restarts itself elevated when needed. Its display
name and registry key default to TopHat-ShooterOS; they must match the `Name`
in your `.ini` file, and can be changed with
`-d:AppDisplayName=...` and `-d:AppRegKey=Software\Microsoft\Windows\CurrentVersion\Uninstall\<Name>`.

License
-------
This project is distributed under the MIT License. See `copying.txt` for the full license text and attribution details.
