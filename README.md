`load` is a personal script to load my frequently used apps and preferences in a new machine.

### 🍏 macOS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh)
```

### 🪟 Windows

```powershell
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1").Content))
```

Alternative:
```powershell
$f="$env:TEMP\load-win.ps1"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile $f -ErrorAction Stop; if(-not ((Get-Content $f -Raw).TrimEnd().EndsWith('# === END load-win.ps1 ==='))){throw "download incomplete - try again"}; powershell -ExecutionPolicy Bypass -File $f
```

Bare command runs on --fast mode first, then pauses before continuing into --full. --dry-run is also available.

### macOS 🍎

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/unload-mac.sh)
```

### Windows 🚪

```powershell
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/unload-win.ps1").Content))
```
