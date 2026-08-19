#!/usr/bin/env bash

set -Eeuo pipefail

# Configure GitHub repository settings
# This script sets up recommended settings for branch protection, merge options, and more

# Auto-detect repo and default branch from git remote
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')

echo "Configuring GitHub settings for $REPO"
echo "Default branch: $BRANCH"
echo ""

# Helper function to prompt for confirmation
confirm() {
    local prompt="$1"
    local response
    read -r -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Helper to check and prompt for a boolean repo setting
check_repo_setting() {
    local setting="$1"
    local desired="$2"
    local description="$3"
    local current
    current=$(echo "$CURRENT_SETTINGS" | jq -r ".$setting")

    if [[ "$current" == "$desired" ]]; then
        return
    fi

    local action current_desc
    if [[ "$desired" == "true" ]]; then
        action="Enable"
        current_desc="currently disabled"
    else
        action="Disable"
        current_desc="currently enabled"
    fi

    if confirm "$action $description? ($current_desc)"; then
        gh api "repos/${REPO}" --method PATCH --field "$setting=$desired" > /dev/null
        echo "  Updated."
    fi
}

# ============================================================================
# Repository Settings
# ============================================================================

echo "=== Repository Settings ==="
echo ""

# Get current repo settings
CURRENT_SETTINGS=$(gh api "repos/${REPO}")

check_repo_setting "allow_squash_merge"      "false" "squash merging"
check_repo_setting "allow_merge_commit"      "true"  "merge commits"
check_repo_setting "allow_rebase_merge"      "true"  "rebase merging"
check_repo_setting "allow_auto_merge"        "true"  "auto-merge"
check_repo_setting "delete_branch_on_merge"  "true"  "delete branch on merge"
check_repo_setting "allow_update_branch"     "true"  "updating PR branches"

echo ""

# ============================================================================
# Branch Protection
# ============================================================================

echo "=== Branch Protection ($BRANCH) ==="
echo ""

# Check current branch protection
CURRENT_PROTECTION=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null) || CURRENT_PROTECTION='{}'

# Get current values (with defaults for missing protection)
BP_CONTEXTS=$(echo "$CURRENT_PROTECTION" | jq -c '.required_status_checks.contexts // []')
BP_STRICT=$(echo "$CURRENT_PROTECTION" | jq -r '.required_status_checks.strict // false')
BP_LINEAR_HISTORY=$(echo "$CURRENT_PROTECTION" | jq -r '.required_linear_history.enabled // false')
BP_ALLOW_FORCE_PUSHES=$(echo "$CURRENT_PROTECTION" | jq -r '.allow_force_pushes.enabled // false')

UPDATE_PROTECTION=false

# Helper to check and prompt for branch protection boolean setting
check_protection_bool() {
    local var_name="$1"
    local desired="$2"
    local description="$3"
    local current="${!var_name}"

    if [[ "$current" == "$desired" ]]; then
        return
    fi

    local action current_desc
    if [[ "$desired" == "true" ]]; then
        action="Enable"
        current_desc="currently disabled"
    else
        action="Disable"
        current_desc="currently enabled"
    fi

    if confirm "$action $description? ($current_desc)"; then
        UPDATE_PROTECTION=true
        printf -v "$var_name" '%s' "$desired"
    fi
}

# Check required status checks (special case - not a simple bool)
if [[ "$BP_CONTEXTS" != '["All checks"]' ]]; then
    if confirm "Set required status checks to [\"All checks\"]? (currently $BP_CONTEXTS)"; then
        UPDATE_PROTECTION=true
        BP_CONTEXTS='["All checks"]'
        BP_STRICT=true
    fi
fi

check_protection_bool "BP_STRICT"             "true"  "require branches to be up to date"
check_protection_bool "BP_LINEAR_HISTORY"     "true"  "require linear history"
check_protection_bool "BP_ALLOW_FORCE_PUSHES" "false" "force pushes by anyone with repository write access"

# Apply branch protection changes if any
if [[ "$UPDATE_PROTECTION" == "true" ]]; then
    echo "Updating branch protection..."

    PROTECTION_PAYLOAD=$(jq -c \
        --argjson status_checks_strict "$BP_STRICT" \
        --argjson status_check_contexts "$BP_CONTEXTS" \
        --argjson required_linear_history "$BP_LINEAR_HISTORY" \
        --argjson allow_force_pushes "$BP_ALLOW_FORCE_PUSHES" \
        '
        def actor_names($property): map(.[$property]);

        {
            required_status_checks: {
                strict: $status_checks_strict,
                contexts: $status_check_contexts
            },
            enforce_admins: (.enforce_admins.enabled // null),
            required_pull_request_reviews: (
                if .required_pull_request_reviews == null then
                    null
                else
                    .required_pull_request_reviews
                    | {
                        dismiss_stale_reviews,
                        require_code_owner_reviews,
                        required_approving_review_count,
                        require_last_push_approval
                    }
                    + if .dismissal_restrictions == null then
                        {}
                    else
                        {
                            dismissal_restrictions: {
                                users: (.dismissal_restrictions.users // [] | actor_names("login")),
                                teams: (.dismissal_restrictions.teams // [] | actor_names("slug")),
                                apps: (.dismissal_restrictions.apps // [] | actor_names("slug"))
                            }
                        }
                    end
                    + if .bypass_pull_request_allowances == null then
                        {}
                    else
                        {
                            bypass_pull_request_allowances: {
                                users: (.bypass_pull_request_allowances.users // [] | actor_names("login")),
                                teams: (.bypass_pull_request_allowances.teams // [] | actor_names("slug")),
                                apps: (.bypass_pull_request_allowances.apps // [] | actor_names("slug"))
                            }
                        }
                    end
                end
            ),
            restrictions: (
                if .restrictions == null then
                    null
                else
                    .restrictions
                    | {
                        users: (.users // [] | actor_names("login")),
                        teams: (.teams // [] | actor_names("slug")),
                        apps: (.apps // [] | actor_names("slug"))
                    }
                end
            ),
            required_linear_history: $required_linear_history,
            allow_force_pushes: $allow_force_pushes,
            allow_deletions: (.allow_deletions.enabled // false),
            block_creations: (.block_creations.enabled // false),
            required_conversation_resolution: (.required_conversation_resolution.enabled // false),
            lock_branch: (.lock_branch.enabled // false),
            allow_fork_syncing: (.allow_fork_syncing.enabled // false)
        }
        ' <<< "$CURRENT_PROTECTION")

    BRANCH_PROTECTION_ENDPOINT="repos/${REPO}/branches/${BRANCH}/protection"
    if BRANCH_PROTECTION_ERROR=$(gh api "$BRANCH_PROTECTION_ENDPOINT" --method PUT --input - <<< "$PROTECTION_PAYLOAD" 2>&1 > /dev/null); then
        echo "  Branch protection updated."
    else
        BRANCH_PROTECTION_STATUS=$?
        printf '  ERROR: gh api PUT %s failed with exit status %d:\n%s\n' \
            "$BRANCH_PROTECTION_ENDPOINT" \
            "$BRANCH_PROTECTION_STATUS" \
            "$BRANCH_PROTECTION_ERROR" >&2
    fi
fi

echo ""

# ============================================================================
# Security Settings
# ============================================================================

echo "=== Security Settings ==="
echo ""

check_security_setting() {
    local endpoint="$1"
    local description="$2"
    local current
    current=$(gh api "repos/${REPO}/$endpoint" --silent && echo "true" || echo "false")

    if [[ "$current" == "true" ]]; then
        return
    fi

    if confirm "Enable $description? (currently disabled)"; then
        gh api "repos/${REPO}/$endpoint" --method PUT
        echo "  Updated."
    fi
}

check_security_setting "vulnerability-alerts"      "vulnerability alerts"
check_security_setting "automated-security-fixes"  "automated security fixes (Dependabot)"

echo ""

# ============================================================================
# Actions Workflow Permissions
# ============================================================================

echo "=== Actions Workflow Permissions ==="
echo ""

WORKFLOW_PERMS=$(gh api "repos/${REPO}/actions/permissions/workflow")
DEFAULT_PERMS=$(echo "$WORKFLOW_PERMS" | jq -r '.default_workflow_permissions')
CAN_APPROVE=$(echo "$WORKFLOW_PERMS" | jq -r '.can_approve_pull_request_reviews')

if [[ "$DEFAULT_PERMS" != "read" ]]; then
    if confirm "Reset default workflow token permissions to read-only? (currently: $DEFAULT_PERMS; workflows needing write should declare a permissions: block)"; then
        gh api "repos/${REPO}/actions/permissions/workflow" --method PUT --field default_workflow_permissions=read > /dev/null
        echo "  Updated."
    fi
fi

if [[ "$CAN_APPROVE" == "true" ]]; then
    if confirm "Disallow Actions from approving pull request reviews? (currently allowed)"; then
        gh api "repos/${REPO}/actions/permissions/workflow" --method PUT --field can_approve_pull_request_reviews=false > /dev/null
        echo "  Updated."
    fi
fi

echo ""

# ============================================================================
# Secrets Audit
# ============================================================================

echo "=== Secrets Audit ==="
echo ""

# Warn about secrets referenced by workflows that don't exist on the repo.
# Secrets can't be restored by script (e.g. after repo recreation), but the gap
# should be surfaced.
WORKFLOWS_DIR="$(git rev-parse --show-toplevel)/.github/workflows"
REFERENCED_SECRETS=$(grep -rhoE 'secrets\.[A-Za-z_][A-Za-z0-9_]*' "$WORKFLOWS_DIR" 2>/dev/null | sed 's/^secrets\.//' | sort -u | grep -vx 'GITHUB_TOKEN' || true)
EXISTING_SECRETS=$(gh api "repos/${REPO}/actions/secrets" --jq '.secrets[].name' 2>/dev/null || true)

if [[ -z "$REFERENCED_SECRETS" ]]; then
    echo "  No secrets referenced by workflows."
else
    MISSING=false
    while IFS= read -r secret; do
        if ! grep -qx "$secret" <<< "$EXISTING_SECRETS"; then
            echo "  WARNING: workflows reference secrets.$secret but no such repo secret exists"
            MISSING=true
        fi
    done <<< "$REFERENCED_SECRETS"
    [[ "$MISSING" == "false" ]] && echo "  All referenced secrets exist."
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "=== Done ==="
