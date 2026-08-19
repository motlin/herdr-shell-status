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
  return_status() {
    return "$1"
  }
  _herdr_shell_status_preexec "true" "true" "true"
  true
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "source plugin" "source plugin" "source plugin"
  source "$1/herdr-shell-status.plugin.zsh"
  _herdr_shell_status_preexec "false" "false" "false"
  false
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "return_status 130" "return_status 130" "return_status 130"
  return_status 130
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "return_status 137" "return_status 137" "return_status 137"
  return_status 137
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "return_status 143" "return_status 143" "return_status 143"
  return_status 143
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
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 130
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 137
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 143
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
' "$plugin_log"

delegate_log="$test_directory/delegate.log"
: > "$delegate_log"
HERDR_TEST_LOG="$delegate_log" zsh -dfi -c '
  export HERDR_TEST_SHELL_PID=$$
  source "$1/herdr-shell-status.plugin.zsh"
  _herdr_shell_status_preexec "claude" "claude" "claude"
  _herdr_shell_status_preexec "/opt/example/claude" "/opt/example/claude" "/opt/example/claude"
  _herdr_shell_status_preexec "EXAMPLE=value command noglob claude" "EXAMPLE=value command noglob claude" "EXAMPLE=value command noglob claude"
  _herdr_shell_status_preexec "env EXAMPLE=value claude" "env EXAMPLE=value claude" "env EXAMPLE=value claude"
  _herdr_shell_status_preexec "sudo claude" "sudo claude" "sudo claude"
  _herdr_shell_status_preexec "time claude" "time claude" "time claude"
  _herdr_shell_status_preexec "env --ignore-environment --unset EXAMPLE /opt/example/claude" "env --ignore-environment --unset EXAMPLE /opt/example/claude" "env --ignore-environment --unset EXAMPLE /opt/example/claude"
  _herdr_shell_status_preexec "sudo --non-interactive --user alice claude" "sudo --non-interactive --user alice claude" "sudo --non-interactive --user alice claude"
  _herdr_shell_status_preexec "time --portability claude" "time --portability claude" "time --portability claude"
  _herdr_shell_status_preexec "env -i sudo -n time -p claude" "env -i sudo -n time -p claude" "env -i sudo -n time -p claude"
  _herdr_shell_status_preexec "env EXAMPLE=value true" "env EXAMPLE=value true" "env EXAMPLE=value true"
  true
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "sudo --non-interactive false" "sudo --non-interactive false" "sudo --non-interactive false"
  false
  _herdr_shell_status_precmd
  _herdr_shell_status_preexec "exec true" "exec true" "exec true"
  _herdr_shell_status_preexec "command noglob exec true" "command noglob exec true" "command noglob exec true"
  _herdr_shell_status_preexec "env exec true" "env exec true" "env exec true"
  false
  _herdr_shell_status_precmd
  herdr_shell_status_disable
' test-shell "$repository_root" >/dev/null 2>&1
assert_file_equals 'pane|process-info|--pane|w-test:p-test
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|idle
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 1
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|working
pane|report-agent|w-test:p-test|--source|user:zsh-command|--agent|cli|--state|blocked|--message|command exited with status 1
pane|release-agent|w-test:p-test|--source|user:zsh-command|--agent|cli
' "$delegate_log"

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

branch_protection_payload="$test_directory/branch-protection-payload.json"
print -r -- y | env \
  GH_TEST_PROTECTION="$repository_root/tests/fixtures/branch-protection.json" \
  GH_TEST_PROTECTION_PAYLOAD="$branch_protection_payload" \
  bash "$repository_root/scripts/configure-github.sh" >/dev/null 2>&1

normalized_branch_protection_payload="$test_directory/normalized-branch-protection-payload.json"
jq --sort-keys . "$branch_protection_payload" > "$normalized_branch_protection_payload"
expected_branch_protection_payload=$(jq --sort-keys . <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["All checks"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismissal_restrictions": {
      "users": ["alice"],
      "teams": ["reviewers"],
      "apps": ["example-review-app"]
    },
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 2,
    "require_last_push_approval": true,
    "bypass_pull_request_allowances": {
      "users": ["bob"],
      "teams": ["maintainers"],
      "apps": ["example-merge-app"]
    }
  },
  "restrictions": {
    "users": ["charlie"],
    "teams": ["deployers"],
    "apps": ["example-deploy-app"]
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": true,
  "block_creations": true,
  "required_conversation_resolution": true,
  "lock_branch": true,
  "allow_fork_syncing": true
}
JSON
)
assert_file_equals "$expected_branch_protection_payload"$'\n' "$normalized_branch_protection_payload"

disabled_branch_protection="$test_directory/disabled-branch-protection.json"
jq '
  .required_status_checks.contexts = ["Old check"]
  | .required_pull_request_reviews = null
  | .restrictions = null
' "$repository_root/tests/fixtures/branch-protection.json" > "$disabled_branch_protection"
print -r -- y | env \
  GH_TEST_PROTECTION="$disabled_branch_protection" \
  GH_TEST_PROTECTION_PAYLOAD="$branch_protection_payload" \
  bash "$repository_root/scripts/configure-github.sh" >/dev/null 2>&1
jq --sort-keys . "$branch_protection_payload" > "$normalized_branch_protection_payload"
expected_disabled_branch_protection_payload=$(print -r -- "$expected_branch_protection_payload" | jq '
  .required_pull_request_reviews = null
  | .restrictions = null
')
assert_file_equals "$expected_disabled_branch_protection_payload"$'\n' "$normalized_branch_protection_payload"

branch_protection_error="$test_directory/branch-protection-error"
print -r -- y | env \
  GH_TEST_PROTECTION="$repository_root/tests/fixtures/branch-protection.json" \
  GH_TEST_PROTECTION_PAYLOAD="$branch_protection_payload" \
  GH_TEST_FAIL_PROTECTION_UPDATE=true \
  bash "$repository_root/scripts/configure-github.sh" >/dev/null 2> "$branch_protection_error"
assert_file_equals '  ERROR: gh api PUT repos/alice/example/branches/main/protection failed with exit status 1:
gh: Validation Failed (HTTP 422)
' "$branch_protection_error"

print 'All tests passed.'
