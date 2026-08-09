# set up `git-test`
setup-git-test:
    git test add --forget --test default 'just --global-justfile _check-local-modifications && (should-skip-commit || just precommit) && just --global-justfile _check-local-modifications'

git_tests := env('GIT_TESTS', "default")
