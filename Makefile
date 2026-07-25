.DEFAULT_GOAL := help
.PHONY: upgrade pre-commit test clean help

upgrade: ## Upgrade dependencies
	npx npm-check-updates -u
	npm install

pre-commit: ## Run all pre-commit hooks
	pre-commit run --all-files

test: ## Run the bats (macOS) and Pester (Windows) test suites
	npm run test
	pwsh -Command Invoke-Pester

clean: ## Remove test artifacts
	rm -f testResults.xml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'
