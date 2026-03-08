#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Core utility functions for git-ai

# Resolve the directory containing this script
#
# Used to locate sibling files (e.g. git_render.awk) relative to git_cmd.sh
# regardless of the caller's working directory.
#
# Usage: _git_cmd_dir     # path to the scripts/ directory
_git_cmd_dir=$(dirname "${BASH_SOURCE[0]}")

# Render a template file by substituting ${VAR} placeholders with env var values
#
# Reads the given template file and uses awk to replace ${VAR} tokens with the
# values of the corresponding environment variables (via ENVIRON[]).
#
# Safety: substitution is a single left-to-right pass — values are never
# re-scanned, so ${...} patterns inside a substituted value (e.g. in a git
# diff) are never expanded. Template files use ALL_CAPS variable names
# (GIT_DIFF, GH_PR_*, etc.) that do not overlap with standard shell variables.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	awk -f "$_git_cmd_dir/git_render.awk" "$template_file"
}

# Resolve the configured agent binary name
#
# Reads ai.agent from git config (default: claude).
#
# Usage: _get_agent       # prints binary name to stdout
_get_agent() {
	local agent
	agent=$(git config ai.agent 2>/dev/null || true)
	printf '%s' "${agent:-claude}"
}

# Send a prompt to the AI provider and print the response
#
# Reads a prompt from stdin and sends it to the configured AI provider.
# Uses the given model or falls back to ai.model / haiku.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
	local agent
	agent=$(_get_agent)

	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(git config ai.model 2>/dev/null || true)
		agent_model="${agent_model:-haiku}"
	fi

	case "$agent" in
	claude)
		MAX_THINKING_TOKENS=0 claude -p \
			--model="$agent_model" \
			--disable-slash-commands \
			--setting-sources='' \
			--system-prompt='' \
			--tools='' \
			- || true
		;;
	*)
		gum log --level error "Unsupported agent '$agent' (supported: claude)"
		return 1
		;;
	esac
}

# Split arguments on the first `--` separator
#
# Populates two nameref arrays: everything before `--` goes into the first,
# everything after goes into the second.  A second `--` in the tail section
# is kept verbatim (passed through).
#
# Usage: _split_on_separator before_ref after_ref "$@"
_split_on_separator() {
	local -n _before_ref="$1"
	local -n _after_ref="$2"
	shift 2

	_before_ref=()
	_after_ref=()

	while [[ $# -gt 0 ]]; do
		if [[ "$1" == "--" ]]; then
			shift
			_after_ref=("$@")
			return 0
		fi
		_before_ref+=("$1")
		shift
	done
}

# Pre-trust a workspace directory in Claude Code so the trust dialog is skipped.
#
# Claude stores trust decisions in ~/.claude.json under per-workspace keys.
# By injecting the entry before Claude enters the directory, we bypass the
# interactive "trust this folder" prompt that would otherwise block the session.
#
# Usage: _trust_workspace "/path/to/workspace"
_trust_workspace() {
	local workspace_path="$1"
	local claude_json="$HOME/.claude.json"
	local tmp
	tmp=$(mktemp)

	if [[ -f "$claude_json" ]]; then
		jq --arg path "$workspace_path" \
			'.projects[$path].hasTrustDialogAccepted = true' "$claude_json" >"$tmp"
	else
		jq -n --arg path "$workspace_path" \
			'{projects: {($path): {hasTrustDialogAccepted: true}}}' >"$tmp"
	fi

	mv "$tmp" "$claude_json"
}

# Pipe a prompt into the configured agent binary
#
# Verifies jq and agent are available, pre-trusts the current directory,
# then calls the agent with an optional --append-system-prompt. Extra
# positional args are forwarded to the agent.
#
# Usage: _cmd_chat "system prompt" [AGENT_ARGS...]
_cmd_chat() {
	local prompt="$1"
	shift

	if ! command -v jq &>/dev/null; then
		gum log --level error "jq is required for chat (https://jqlang.github.io/jq/download)"
		return 1
	fi

	local agent
	agent=$(_get_agent)
	if ! command -v "$agent" &>/dev/null; then
		gum log --level error "Agent '$agent' not found"
		gum log --level info "Install it or set: git config ai.agent <binary>"
		return 1
	fi

	# Pre-trust the project root so the agent doesn't prompt the user to
	# trust the directory when starting a session.
	_trust_workspace "$(pwd -P)"

	if [[ -n "$prompt" ]]; then
		"$agent" --append-system-prompt "$prompt" "$@"
	else
		"$agent" "$@"
	fi
}

# Resolve the git repository root directory
#
# Writes the result into the nameref; returns 1 and logs an error on failure.
#
# Usage: _git_repo_path git_dir_ref
_git_repo_path() {
	local -n _git_dir_ref="$1"
	_git_dir_ref=$(git rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -z "$_git_dir_ref" ]]; then
		gum log --level error "Not inside a git repository"
		return 1
	fi
}

# Resolve the main worktree root, even when called from a linked worktree.
#
# git rev-parse --git-common-dir returns the shared .git directory path;
# its parent is always the main worktree root regardless of which worktree
# is currently active.
#
# Writes the result into the nameref; returns 1 and logs an error on failure.
#
# Usage: _git_main_worktree_path path_ref
_git_main_worktree_path() {
	local -n _gmwp_ref="$1"
	local _gmwp_common_dir
	_gmwp_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
	if [[ -z "$_gmwp_common_dir" ]]; then
		gum log --level error "Not inside a git repository"
		return 1
	fi
	_gmwp_ref=$(cd "$_gmwp_common_dir/.." && pwd -P)
}

# Resolve the base directory for persistent chat sessions.
# Always <worktree-root>/.git/sessions.
#
# Stdout: base directory path
# Usage: base=$(_git_session_base_dir <git_root>)
_git_session_base_dir() {
	printf '%s/.git/sessions' "$1"
}

# Create a temporary context directory for ask-mode commands
#
# Creates a temp directory that can hold large context files. Caller is
# responsible for cleanup (rm -rf) after use.
#
# Usage: _create_context_dir context_dir_ref
_create_context_dir() {
	local -n _cdir_ref="$1"
	local _ctx_tmpdir="${TMPDIR:-/tmp}"
	_cdir_ref=$(mktemp -d "${_ctx_tmpdir%/}/git-ai-ctx.XXXXXXXXXX")
}

# Resolve context directory: persistent session dir for chat, temp dir otherwise
#
# Chat commands get a persistent directory under .git/sessions/<name>;
# all other commands get a temporary directory via _create_context_dir.
#
# Usage: _resolve_context_dir type session_name dir_ref
_resolve_context_dir() {
	local _rcd_type="$1"
	local _rcd_name="$2"
	local -n _rcd_dir="$3"

	if [[ "$_rcd_type" == "chat" ]]; then
		local _rcd_git_root
		_git_main_worktree_path _rcd_git_root || return 1
		_rcd_dir="$(_git_session_base_dir "$_rcd_git_root")/$_rcd_name"
		mkdir -p "$_rcd_dir"
	else
		_create_context_dir _rcd_dir
	fi
}

# Save content to a named file in a context directory
#
# Writes content to a file using printf builtin (no execve, so no ARG_MAX impact).
#
# Usage: _save_context_file "/path/to/context/dir" "filename" "content"
_save_context_file() {
	local dir="$1" name="$2" content="$3"
	printf '%s' "$content" >"$dir/$name"
}

# Validate chat passthrough args, rejecting flags managed by git-ai.
#
# Returns 1 if --session-id or --resume are found.
#
# Usage: _validate_chat_passthrough passthrough_ref
_validate_chat_passthrough() {
	local -n _vcp_args="$1"
	local _vcp_flag
	for _vcp_flag in "${_vcp_args[@]}"; do
		case "$_vcp_flag" in
		--session-id | --resume)
			gum log --level error "$_vcp_flag is managed by git-ai and cannot be passed through"
			return 1
			;;
		esac
	done
}

# Resolve session arguments for _cmd_chat and report whether a new session
# is being started.
#
# Reads the session UUID from $session_dir/session.id.
#   - File present and new_session is empty: sets is_new_ref to "" and
#     args_ref to (--resume <uuid>).
#   - File absent or new_session is non-empty: generates a new UUID, writes it
#     to the file, sets is_new_ref to 1 and args_ref to (--session-id <uuid>).
#
# Usage: _resolve_chat_session session_dir new_session is_new_ref args_ref
_resolve_chat_session() {
	local _rcs_dir="$1"
	local _rcs_new_session="$2"
	local -n _rcs_is_new="$3"
	local -n _rcs_args="$4"

	local _rcs_session_file="$_rcs_dir/session.id"
	local _rcs_uuid

	if [[ -n "$_rcs_new_session" ]]; then
		rm -fr "$_rcs_session_file"
	fi

	if [[ -f "$_rcs_session_file" ]]; then
		_rcs_uuid=$(<"$_rcs_session_file")
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=""
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=(--resume "$_rcs_uuid")
	else
		_rcs_uuid=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
		if [[ -z "$_rcs_uuid" ]]; then
			gum log --level error "Failed to generate session UUID"
			return 1
		fi
		printf '%s' "$_rcs_uuid" >"$_rcs_session_file"
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=1
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=(--session-id "$_rcs_uuid")
	fi
}

# Build diff context shared by explain and chat commands.
#
# Computes a git diff based on the provided refs, saves it to a file in
# the context directory, and populates five output namerefs.
#
# Modes:
#   ref1 + ref2         → git diff ref1 ref2
#   ref1 containing ..  → git diff ref1  (already a range)
#   ref1 only           → git diff ref1...HEAD
#   no refs             → git diff --staged
#
# Usage: _prepare_diff_context ref1 ref2 staged ctx_dir \
#            diff_file_ref diff_stat_ref diff_refs_ref commits_ref branch_ref
_prepare_diff_context() {
	local _pdc_ref1="$1"
	local _pdc_ref2="$2"
	local _pdc_staged="$3"
	local _pdc_ctx_dir="$4"
	local -n _pdc_diff_file="${5}"
	local -n _pdc_diff_stat="${6}"
	local -n _pdc_diff_refs="${7}"
	local -n _pdc_commits="${8}"
	local -n _pdc_branch="${9}"

	local _pdc_diff _pdc_log

	if [[ -n "$_pdc_ref2" ]]; then
		# Two separate refs
		_pdc_diff=$(git diff "$_pdc_ref1" "$_pdc_ref2" 2>/dev/null || true)
		_pdc_diff_stat=$(git diff "$_pdc_ref1" "$_pdc_ref2" --stat 2>/dev/null || true)
		_pdc_log=$(git log --oneline "$_pdc_ref1..$_pdc_ref2" 2>/dev/null || true)
		_pdc_diff_refs="$_pdc_ref1..$_pdc_ref2"
	elif [[ -n "$_pdc_ref1" && "$_pdc_ref1" == *..* ]]; then
		# ref1 is already a range expression (e.g. HEAD~3..HEAD)
		_pdc_diff=$(git diff "$_pdc_ref1" 2>/dev/null || true)
		_pdc_diff_stat=$(git diff "$_pdc_ref1" --stat 2>/dev/null || true)
		_pdc_log=$(git log --oneline "$_pdc_ref1" 2>/dev/null || true)
		_pdc_diff_refs="$_pdc_ref1"
	elif [[ -n "$_pdc_ref1" ]]; then
		# Single ref: show changes between that ref and HEAD
		_pdc_diff=$(git diff "$_pdc_ref1...HEAD" 2>/dev/null || true)
		_pdc_diff_stat=$(git diff "$_pdc_ref1...HEAD" --stat 2>/dev/null || true)
		_pdc_log=$(git log --oneline "$_pdc_ref1..HEAD" 2>/dev/null || true)
		_pdc_diff_refs="$_pdc_ref1...HEAD"
	else
		# Default: staged changes
		_pdc_diff=$(git diff --staged 2>/dev/null || true)
		_pdc_diff_stat=$(git diff --staged --stat 2>/dev/null || true)
		_pdc_log=""
		_pdc_diff_refs="staged"
	fi

	if [[ -z "$_pdc_diff" ]]; then
		gum log --level error "No diff found"
		if [[ -z "$_pdc_ref1" ]]; then
			gum log --level info "Stage your changes with 'git add' first"
		fi
		return 1
	fi

	_save_context_file "$_pdc_ctx_dir" "diff.patch" "$_pdc_diff"
	# shellcheck disable=SC2034 # nameref: set by caller
	_pdc_diff_file="$_pdc_ctx_dir/diff.patch"

	_save_context_file "$_pdc_ctx_dir" "diff_stat.txt" "$_pdc_diff_stat"

	# shellcheck disable=SC2034 # nameref: set by caller
	_pdc_commits=$(printf '%s\n' "$_pdc_log" | sed 's/^[a-f0-9]* /- /')

	# shellcheck disable=SC2034 # nameref: set by caller
	_pdc_branch=""
	if git rev-parse HEAD &>/dev/null 2>&1; then
		_pdc_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	fi
}

main() {
	local cmd
	cmd="${1:-}"

	case "$cmd" in
	render)
		_cmd_render "${2:-}"
		;;
	ask)
		_cmd_ask "${2:-}"
		;;
	chat)
		shift
		_cmd_chat "$@"
		;;
	*)
		gum log --level error "Usage: git_cmd.sh <render|ask|chat> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
