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
    shellcheck bin/check scripts/configure-github.sh tests/fixtures/gh tests/fixtures/herdr

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

# Fail unless the version is `1.2.3` shaped and unused
_check-release-version version:
    #!/usr/bin/env bash
    set -Eeuo pipefail

    VERSION="{{version}}"

    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
        {{echo_command}} "Version must look like 1.2.3, got '$VERSION'"
        exit 1
    fi

    if git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null; then
        {{echo_command}} "Tag v$VERSION already exists"
        exit 1
    fi

# Validate, tag, and push a release, like `just release 0.2.1`
release version: (_check-release-version version) _check-local-modifications precommit
    #!/usr/bin/env bash
    set -Eeuo pipefail

    TAG="v{{version}}"
    BRANCH="$(git symbolic-ref --short HEAD)"

    if [ "$BRANCH" != "{{upstream_branch}}" ]; then
        {{echo_command}} "Releases happen on {{upstream_branch}}, but HEAD is on $BRANCH"
        exit 1
    fi

    git fetch origin "{{upstream_branch}}"

    if ! git merge-base --is-ancestor "origin/{{upstream_branch}}" HEAD; then
        {{echo_command}} "Local {{upstream_branch}} is behind or diverged from origin/{{upstream_branch}}; update it first"
        exit 1
    fi

    git tag "$TAG"
    trap 'git tag --delete "$TAG" >/dev/null 2>&1 || true' ERR
    git push --atomic origin "HEAD:refs/heads/{{upstream_branch}}" "refs/tags/$TAG"
    trap - ERR

@clean: _clean-git

echo_command := env('ECHO_COMMAND', "echo")
