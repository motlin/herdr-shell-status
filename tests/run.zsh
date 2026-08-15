#!/usr/bin/env zsh

set -eu

repository_root="${0:A:h:h}"
test_directory="$(mktemp -d "$repository_root/.test.XXXXXX")"
trap 'rm -rf -- "$test_directory"' EXIT

export PATH="$repository_root/tests/fixtures:$PATH"
export HERDR_BIN_PATH="$repository_root/tests/fixtures/herdr"
export HERDR_ENV=1
export HERDR_PANE_ID='w-test:p-test'

fail() {
  print -u2 -r -- "$1"
  exit 1
}

assert_file_equals() {
  local expected="$1"
  local actual_file="$2"
  local expected_file="$test_directory/expected"
  print -rn -- "$expected" > "$expected_file"
  diff -u "$expected_file" "$actual_file" || fail "Unexpected lifecycle calls"
}

plugin_log="$test_directory/plugin.log"
: > "$plugin_log"
HERDR_TEST_LOG="$plugin_log" zsh -dfi -c '
  export HERDR_TEST_SHELL_PID=$$
  source "$1/herdr-shell-status.plugin.zsh"
  _herdr_shell_status_preexec "true" "true" "true"
  true
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "source plugin" "source plugin" "source plugin"
  source "$1/herdr-shell-status.plugin.zsh"
  _herdr_shell_status_preexec "false" "false" "false"
  false
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "claude" "claude" "claude"
  herdr_shell_status_disable
' test-shell "$repository_root" >/dev/null 2>&1
assert_file_equals 'pane|process-info|--pane|w-test:p-test
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|idle
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|process-info|--pane|w-test:p-test
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 1
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
' "$plugin_log"

nested_log="$test_directory/nested.log"
: > "$nested_log"
HERDR_TEST_LOG="$nested_log" HERDR_TEST_SHELL_PID=999999 zsh -dfi -c '
  source "$1/herdr-shell-status.plugin.zsh"
  if (( ${+preexec_functions} )); then
    (( ${preexec_functions[(Ie)_herdr_shell_status_preexec]} == 0 ))
  fi
' test-shell "$repository_root" >/dev/null 2>&1
assert_file_equals 'pane|process-info|--pane|w-test:p-test
' "$nested_log"

noninteractive_log="$test_directory/noninteractive.log"
: > "$noninteractive_log"
HERDR_TEST_LOG="$noninteractive_log" zsh -dfc '
  source "$1/herdr-shell-status.plugin.zsh"
  (( ${+functions[_herdr_shell_status_preexec]} ))
' test-shell "$repository_root"
assert_file_equals '' "$noninteractive_log"

missing_jq_log="$test_directory/missing-jq.log"
missing_jq_stderr="$test_directory/missing-jq.stderr"
: > "$missing_jq_log"
HERDR_TEST_LOG="$missing_jq_log" zsh -dfi -c '
  export HERDR_TEST_SHELL_PID=$$
  path=()
  source "$1/herdr-shell-status.plugin.zsh"
' test-shell "$repository_root" >/dev/null 2> "$missing_jq_stderr"
grep -q 'jq' "$missing_jq_stderr" || fail "Expected a jq warning on stderr when jq is missing inside a Herdr pane"
assert_file_equals '' "$missing_jq_log"

outside_stderr="$test_directory/outside.stderr"
HERDR_ENV=0 zsh -dfi -c '
  path=()
  source "$1/herdr-shell-status.plugin.zsh"
' test-shell "$repository_root" >/dev/null 2> "$outside_stderr"
assert_file_equals '' "$outside_stderr"
print 'All tests passed.'
