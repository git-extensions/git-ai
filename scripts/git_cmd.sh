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

# Pipe a prompt into the configured agent binary
#
# Verifies the agent is available, then launches it with --append-system-prompt.
# Extra positional args are forwarded to the agent.
#
# Usage: _cmd_chat "system prompt" [AGENT_ARGS...]
_cmd_chat() {
	local prompt="$1"
	shift

	local agent
	agent=$(_get_agent)
	if ! command -v "$agent" &>/dev/null; then
		gum log --level error "Agent '$agent' not found"
		gum log --level info "Install it or set: git config ai.agent <binary>"
		return 1
	fi

	"$agent" --append-system-prompt "$prompt" "$@"
}

# Create a temporary context directory
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

# Save content to a named file in a context directory
#
# Writes content to a file using printf builtin (no execve, so no ARG_MAX impact).
#
# Usage: _save_context_file "/path/to/context/dir" "filename" "content"
_save_context_file() {
	local dir="$1" name="$2" content="$3"
	printf '%s' "$content" >"$dir/$name"
}

# Build diff context shared by explain and chat commands.
#
# Computes a git diff based on the provided refs, writes three context files
# to ctx_dir, and populates two output namerefs.
#
# Files written to ctx_dir:
#   diff.patch      — full unified diff
#   diff_stat.txt   — diffstat summary
#   commits.txt     — formatted commit log (one per line, "- <msg>")
#
# Modes:
#   ref1 + ref2         → git diff ref1 ref2
#   ref1 containing ..  → git diff ref1  (already a range)
#   ref1 only           → git diff ref1...HEAD
#   no refs             → git diff --staged
#
# Usage: _prepare_diff_context ref1 ref2 staged ctx_dir diff_refs_ref branch_ref
_prepare_diff_context() {
	local _pdc_ref1="$1"
	local _pdc_ref2="$2"
	local _pdc_staged="$3"
	local _pdc_ctx_dir="$4"
	local -n _pdc_diff_refs="${5}"
	local -n _pdc_branch="${6}"

	local _pdc_diff _pdc_diff_stat _pdc_log

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
	_save_context_file "$_pdc_ctx_dir" "diff_stat.txt" "$_pdc_diff_stat"
	_save_context_file "$_pdc_ctx_dir" "commits.txt" \
		"$(printf '%s\n' "$_pdc_log" | sed 's/^[a-f0-9]* /- /')"

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
	*)
		gum log --level error "Usage: git_cmd.sh <render|ask> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
