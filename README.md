`load` is a personal script to load my frequently used apps and preferences in a new machine.

### 🚗 Auto Set Up

Bare command runs on --fast mode first, then pauses before continuing into --full. --dry-run is also available.

* macOS:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh)
```

* Windows:
```powershell
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1").Content))
```

* Windows (alternative):
```powershell
$f="$env:TEMP\load-win.ps1"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile $f -ErrorAction Stop; if(-not ((Get-Content $f -Raw).TrimEnd().EndsWith('# === END load-win.ps1 ==='))){throw "download incomplete - try again"}; powershell -ExecutionPolicy Bypass -File $f
```


### 🧪 Pre-requisites (only for Tests)

1) Install Node (with [bats](https://github.com/bats-core/bats-core).) and Powershell (with [Pester](https://pester.dev)):
```bash
brew install node bats-core powershell
pwsh -Command "Install-Module Pester -Scope CurrentUser"
```

2) From inside the repo, install `bats` test dependencies (into node_modules):

```bash
npm ci
```

3) Run tests:

```bash
npm run test
pwsh -Command Invoke-Pester
```
