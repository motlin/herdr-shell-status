set dotenv-filename := ".envrc"

import ".just/console.just"
import ".just/git.just"
import ".just/git-test.just"

# `just --list --unsorted`
default:
    @just --list --unsorted

# Install pinned development tools
mise:
    mise install --quiet
    mise current

# vp fmt
format:
    vp fmt

# Validate Bash and Zsh source files
lint:
    zsh -n herdr-shell-status.plugin.zsh
    zsh -n tests/run.zsh
    shellcheck bin/check scripts/configure-github.sh tests/fixtures/herdr

# Run the deterministic fake-Herdr test suite
test: lint
    zsh tests/run.zsh

# pre-commit run --all-files
pre-commit:
    pre-commit run --all-files

# Run every local validation check
precommit: test pre-commit
    @echo "All precommit checks passed!"

# Alias for `precommit`
verify: precommit

@clean: _clean-git

echo_command := env('ECHO_COMMAND', "echo")
