#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Core utility functions for git-ai

# Check if gum is available (memoized).
_has_gum() {
	if [[ -z "${_gum_available+x}" ]]; then
		if command -v gum &>/dev/null; then
			_gum_available=1
		else
			_gum_available=0
		fi
	fi
	[[ "$_gum_available" -eq 1 ]]
}

# Gum wrapper — dispatches to gum when available, falls back to plain
# stderr output otherwise.
# Usage: _gum log --level info "message"
#        _gum spin --title "title" -- cmd [args...]
_gum() {
	local subcmd="$1"
	shift
	case "$subcmd" in
	log)
		if _has_gum; then
			gum log "$@"
		else
			local msg="${*: -1}"
			printf '%s\n' "$msg" >&2
		fi
		;;
	spin)
		if _has_gum; then
			gum spin "$@"
		else
			local title=""
			while [[ $# -gt 0 && "$1" != "--" ]]; do
				if [[ "$1" == "--title" ]]; then shift; title="$1"; fi
				shift
			done
			[[ "$1" == "--" ]] && shift
			[[ -n "$title" ]] && printf '%s\n' "$title" >&2
			"$@"
		fi
		;;
	*)
		return 1
		;;
	esac
}

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
		_gum log --level error "Template not found: $template_file"
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
		_gum log --level error "Unsupported agent '$agent' (supported: claude)"
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
		_gum log --level error "Usage: git_cmd.sh <render|ask> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
