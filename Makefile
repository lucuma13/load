.PHONY: all check lint test

all: check lint test

# Syntax-check the shell entrypoint.
check:
	bash -n src/load-mac.sh

# Lint the shell entrypoint (needs shellcheck: `brew install shellcheck`).
lint:
	shellcheck src/load-mac.sh

# Run the bats test suite (needs bats-core: `brew install bats-core`).
test:
	bats tests/
