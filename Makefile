.DEFAULT_GOAL := help
.PHONY: setup-dev upgrade pre-commit test install clean help

# Process substitution in the install recipe needs bash, not /bin/sh.
SHELL := /bin/bash

setup-dev: ## Install dev pre-requisites (node, PowerShell, Pester, bats)
ifeq ($(OS),Windows_NT)
	winget install -e --silent --accept-package-agreements --accept-source-agreements OpenJS.NodeJS Microsoft.PowerShell
else
	brew install node powershell
endif
	pwsh -Command "Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck"
	npm ci

upgrade: ## Upgrade dependencies
	npx npm-check-updates -u
	npm install

pre-commit: ## Run all pre-commit hooks
	pre-commit run --all-files

test: ## Run the bats (macOS) and Pester (Windows) test suites
	npm run test
	pwsh -Command Invoke-Pester

install: ## Run the published load script on this machine
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -Command '& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1").Content))'
else
	bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh)
endif

clean: ## Remove test artifacts
	rm -f testResults.xml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'
