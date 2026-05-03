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

# Source provider modules
# shellcheck source=scripts/git_cmd_claude.sh
source "$_git_cmd_dir/git_cmd_claude.sh"
# shellcheck source=scripts/git_cmd_codex.sh
source "$_git_cmd_dir/git_cmd_codex.sh"
# shellcheck source=scripts/git_cmd_gemini.sh
source "$_git_cmd_dir/git_cmd_gemini.sh"

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

# Resolve the default model for an AI provider
#
# Usage: _get_agent_default_model AGENT
_get_agent_default_model() {
	case "$1" in
	claude)
		_get_claude_default_model
		;;
	codex)
		_get_codex_default_model
		;;
	gemini)
		_get_gemini_default_model
		;;
	*)
		gum log --level error "Unsupported agent '$1' (supported: claude, codex, gemini)"
		return 1
		;;
	esac
}

# Resolve the configured model name
#
# Uses the given model or falls back to ai.model / an agent-specific default.
#
# Usage: _get_agent_model AGENT [MODEL]
_get_agent_model() {
	local agent="$1"
	local agent_model="${2:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(git config ai.model 2>/dev/null || true)
	fi
	if [[ -z "$agent_model" ]]; then
		agent_model=$(_get_agent_default_model "$agent")
	fi
	printf '%s' "$agent_model"
}

# Send a prompt to the AI provider and print the response
#
# Reads a prompt from stdin and sends it to the configured AI provider.
# Uses the given model or falls back to ai.model / an agent-specific default.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
	local agent
	agent=$(_get_agent)

	local agent_model
	agent_model=$(_get_agent_model "$agent" "${1:-}")

	case "$agent" in
	claude)
		_ask_claude "$agent_model"
		;;
	codex)
		_ask_codex "$agent_model"
		;;
	gemini)
		_ask_gemini "$agent_model"
		;;
	*)
		gum log --level error "Unsupported agent '$agent' (supported: claude, codex, gemini)"
		return 1
		;;
	esac
}

_git_cmd_main() {
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
	_git_cmd_main "$@"
fi
