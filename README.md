## 🚗 Set Up Workstation

Run the line for your OS. It runs on --fast mode first, then
pauses and asks whether to continue into --full.

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


### 🧪 Tests (macOS `bats`)

The macOS tests run on [bats](https://github.com/bats-core/bats-core). Its
libraries (`bats`, `bats-support`, `bats-assert`) are managed as npm
devDependencies, so they're pinned in `package-lock.json` and tracked by
Dependabot for new releases. `bats-support` is pulled straight from the
official `bats-core/bats-support` git repo (the npm registry copy is a fork),
pinned by tag via `#semver:^0.3.0`.

> **CI note:** npm records the `bats-support` git source as an `ssh://` URL in
> the lockfile. Local installs work over your normal GitHub SSH keys; the CI
> workflow has no SSH keys, so it rewrites that source to https before
> `npm ci`:
> ```bash
> git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
> ```


Install Node:
```bash
brew install node
```

Update the libraries:

```bash
npm outdated      # see what's behind
npm update        # bump within the package.json ranges
```

Install test deps and run:

```bash
npm ci            # restore pinned bats libraries into node_modules/
npm test          # runs: bats tests
```

### 🧪 Tests (Windows `Pester`)

The Windows tests use [Pester](https://pester.dev). Install it once from the PowerShell Gallery,
then run:
```powershell
Install-Module Pester -Scope CurrentUser   # one-time
Invoke-Pester tests
```
