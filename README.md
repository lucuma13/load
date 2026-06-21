## 🚗 Auto Set Up Workstation

Run the line for your OS. It runs on --fast mode first, then
pauses and continues into --full on a keypress.

* macOS
```bash
curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash
```

* Windows:
```powershell
iwr -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -OutFile "$env:TEMP\load-win.ps1" -UseBasicParsing; powershell.exe -ExecutionPolicy Bypass -File "$env:TEMP\load-win.ps1"
```


## 🧪 Development / Tests

The macOS tests run on [bats](https://github.com/bats-core/bats-core). Its
libraries (`bats`, `bats-support`, `bats-assert`) are managed as npm
devDependencies, so they're pinned in `package-lock.json` and tracked by
Dependabot for new releases. `bats-support` is pulled straight from the
official `bats-core/bats-support` git repo (the npm registry copy is a fork),
pinned by tag via `#semver:^0.3.0`.

CI runs the suite on every push/PR via `.github/workflows/tests.yml`
(`macos-latest`), executing the offline tests (`npm run test:ci`, which skips
the `live` network-dependent ones).

> **CI note:** npm records the `bats-support` git source as an `ssh://` URL in
> the lockfile. Local installs work over your normal GitHub SSH keys; the CI
> workflow has no SSH keys, so it rewrites that source to https before
> `npm ci`:
> ```bash
> git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
> ```

### Prerequisites (fresh macOS)

Install Node (which ships with npm) via Homebrew:
```bash
brew install node
```
If you don't have Homebrew yet:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install test deps and run

```bash
npm ci            # restore pinned bats libraries into node_modules/
npm test          # runs: bats tests
```

### Updating the libraries

```bash
npm outdated      # see what's behind
npm update        # bump within the package.json ranges
```
Dependabot also opens a weekly PR when a new bats version is released.

### Windows tests

The Windows tests use [Pester](https://pester.dev). Install it once from the
PowerShell Gallery, then run:
```powershell
Install-Module Pester -Scope CurrentUser   # one-time
Invoke-Pester tests\windows_premiere.Tests.ps1
```
There's no lockfile/Dependabot for Pester (the PowerShell Gallery isn't a
supported Dependabot ecosystem), so its version is managed manually.

<!--
* Windows alternative with Bypass upfront: powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1 | iex"

* Windows alternative with irm: irm "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -OutFile "$env:TEMP\load-win.ps1"; powershell.exe -ExecutionPolicy Bypass -File "$env:TEMP\load-win.ps1"

-UseBasicParsing -> needed with iwr for powershell 5.1
Set-Content "$env:TEMP\load-win.ps1" -> avoid, it may introduce CRLF
-OutFile "$env:TEMP\load-win.ps1" -> raw bytes the same, creates new file
-Encoding UTF8 -> avoid, BOM
-->
