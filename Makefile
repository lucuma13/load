.DEFAULT_GOAL := help
.PHONY: setup-dev upgrade pre-commit test load unload clean help

ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /C
else
# Process substitution in the install recipe needs bash, not /bin/sh.
SHELL := /bin/bash
endif

setup-dev: ## Install dev pre-requisites (node, PowerShell, Pester, bats, pre-commit)
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -Command "winget install -e --silent --accept-package-agreements --accept-source-agreements OpenJS.NodeJS Microsoft.PowerShell astral-sh.uv; $$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User'); pwsh -Command 'Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck'; npm ci; uv tool install pre-commit; uv tool update-shell; uv tool run pre-commit install"
else
	brew install node powershell pre-commit
	pwsh -Command "Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck"
	npm ci
	pre-commit install
endif

upgrade: ## Upgrade dependencies
	npx npm-check-updates -u
	npm install

pre-commit: ## Run all pre-commit hooks
	pre-commit run --all-files

test: ## Run the test suites (bats + Pester on macOS, Pester on Windows)
ifeq ($(OS),Windows_NT)
# Only Pester, no bats available on Windows.
	pwsh -Command Invoke-Pester
else
	npm run test
	pwsh -Command Invoke-Pester
endif

load: ## Run the published load script on this machine
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -Command "& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1').Content))"
else
	bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh)
endif

unload: ## Run the published unload script on this machine
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -Command "& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/lucuma13/load/main/src/unload-win.ps1').Content))"
else
	bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/unload-mac.sh)
endif

clean: ## Remove test artifacts
ifeq ($(OS),Windows_NT)
	if exist testResults.xml del /q testResults.xml
else
	rm -f testResults.xml
endif

help: ## Show this help
ifeq ($(OS),Windows_NT)
	@powershell -NoProfile -Command "$$e = [char]27; Select-String -Path '$(MAKEFILE_LIST)' -Pattern '^([a-zA-Z_-]+):.*?## (.*)$$' | ForEach-Object { $$g = $$_.Matches[0].Groups; '  {0}[36m{1,-11}{0}[0m {2}' -f $$e, $$g[1].Value, $$g[2].Value }"
else
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'
endif
