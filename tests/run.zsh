#!/usr/bin/env zsh

set -eu

repository_root="${0:A:h:h}"
test_directory="$(mktemp -d "$repository_root/.test.XXXXXX")"
trap 'rm -rf -- "$test_directory"' EXIT

export PATH="$repository_root/tests/fixtures:$PATH"
export HERDR_BIN_PATH="$repository_root/tests/fixtures/herdr"
export HERDR_ENV=1
export HERDR_PANE_ID='w-test:p-test'
export HERDR_TEST_FOCUSED=true

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

assert_file_equals_with_normalized_process_id() {
  local expected="$1"
  local actual_file="$2"
  local normalized_file="$test_directory/normalized"
  sed -E 's/user:herdr-run:[0-9]+/user:herdr-run:PID/g' "$actual_file" > "$normalized_file"
  assert_file_equals "$expected" "$normalized_file"
}

wait_for_line_count() {
  local expected_count="$1"
  local log_file="$2"
  local attempt
  local actual_count

  for attempt in {1..100}; do
    actual_count="$(wc -l < "$log_file" | tr -d ' ')"
    (( actual_count >= expected_count )) && return 0
    sleep 0.02
  done

  fail "Timed out waiting for lifecycle calls"
}

plugin_log="$test_directory/plugin.log"
: > "$plugin_log"
HERDR_TEST_LOG="$plugin_log" zsh -dfi -c '
  export HERDR_TEST_SHELL_PID=$$
  source "$1/herdr-shell-status.plugin.zsh"
  _herdr_shell_status_preexec "true" "true" "true"
  true
  _herdr_shell_status_precmd
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

success_log="$test_directory/success.log"
: > "$success_log"
HERDR_TEST_LOG="$success_log" HERDR_TEST_SHELL_PID=$$ \
  "$repository_root/bin/herdr-run" --label build -- true
wait_for_line_count 4 "$success_log"
assert_file_equals_with_normalized_process_id 'pane|report-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build|--state|working
pane|report-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build|--state|idle
pane|get|w-test:p-test
pane|release-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build
' "$success_log"

failure_log="$test_directory/failure.log"
: > "$failure_log"
set +e
HERDR_TEST_LOG="$failure_log" HERDR_TEST_SHELL_PID=$$ \
  "$repository_root/bin/herdr-run" --label build -- false
failure_status=$?
set -e
[[ "$failure_status" == 1 ]] || fail "Expected failure status 1, got $failure_status"
wait_for_line_count 4 "$failure_log"
assert_file_equals_with_normalized_process_id 'pane|report-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build|--state|working
pane|report-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build|--state|blocked|--message|command exited with status 1
pane|get|w-test:p-test
pane|release-agent|w-test:p-test|--source|user:herdr-run:PID|--agent|build
' "$failure_log"

outside_log="$test_directory/outside.log"
: > "$outside_log"
HERDR_ENV=0 HERDR_TEST_LOG="$outside_log" \
  "$repository_root/bin/herdr-run" -- sh -c 'exit 7' || outside_status=$?
[[ "${outside_status:-0}" == 7 ]] || fail "Expected passthrough status 7, got ${outside_status:-0}"
assert_file_equals '' "$outside_log"

print 'All tests passed.'
