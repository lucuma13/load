.PHONY: test check

# Run the bats test suite (needs bats-core: `brew install bats-core`).
test:
	bats tests/

# Syntax-check the shell entrypoint.
check:
	bash -n src/load-mac.sh
