#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Chat help function
#
# Displays help information for the chat command
# including usage examples and available options.
_show_chat_help() {
	cat <<'EOF'
git ai chat - Open an interactive AI session with git diff context

USAGE:
    git ai chat [REF1 [REF2]] [--staged] [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

DESCRIPTION:
    Starts an interactive AI session with the diff as a system prompt context.
    Each invocation starts a fresh session.

    No args / --staged  → git diff --staged (default)
    Single ref          → git diff <ref>...HEAD
    Range (ref1..ref2)  → git diff <ref1>..<ref2>
    Two refs            → git diff <ref1> <ref2>

FLAGS:
    -d, --description <TEXT>    Extra context or focus for the session
    -- AGENT_OPTIONS            Options passed directly to the agent binary

EXAMPLES:
    git ai chat                             # chat about staged changes
    git ai chat HEAD~3                      # chat about changes since HEAD~3
    git ai chat main                        # chat about changes since main
    git ai chat HEAD~3..HEAD                # explicit range
    git ai chat pr-122-branch               # chat about branch divergence
    git ai chat -d "any security issues?"   # with extra focus
    git ai chat -- --model sonnet           # pass model to agent
EOF
}

# Parse chat arguments (before -- separator)
#
# Extracts up to two optional ref positional args, --staged flag,
# and -d/--description value. Unknown flags produce an error.
#
# Usage: _parse_chat_args_git ref1_ref ref2_ref staged_ref desc_ref [args...]
_parse_chat_args_git() {
	local -n _pcag_ref1="$1"
	local -n _pcag_ref2="$2"
	local -n _pcag_staged="$3"
	local -n _pcag_desc="$4"
	shift 4

	local _pcag_raw=("$@")
	local _pcag_skip=false
	local _pcag_i=0

	while [[ $_pcag_i -lt ${#_pcag_raw[@]} ]]; do
		if [[ "$_pcag_skip" = true ]]; then
			_pcag_skip=false
			(( ++_pcag_i ))
			continue
		fi

		case "${_pcag_raw[$_pcag_i]}" in
		--staged)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pcag_staged=1
			;;
		--description | -d)
			if ((_pcag_i + 1 >= ${#_pcag_raw[@]})); then
				gum log --level error "${_pcag_raw[$_pcag_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_pcag_desc="${_pcag_raw[$((_pcag_i + 1))]}"
			_pcag_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pcag_desc="${_pcag_raw[$_pcag_i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${_pcag_raw[$_pcag_i]}'"
			return 1
			;;
		*)
			if [[ -z "$_pcag_ref1" ]]; then
				_pcag_ref1="${_pcag_raw[$_pcag_i]}"
			elif [[ -z "$_pcag_ref2" ]]; then
				_pcag_ref2="${_pcag_raw[$_pcag_i]}"
			else
				gum log --level error "unexpected argument '${_pcag_raw[$_pcag_i]}'"
				return 1
			fi
			;;
		esac
		(( ++_pcag_i ))
	done
}

# Main chat command implementation
#
# Starts an interactive AI session scoped to a git diff. Builds diff context
# from the provided refs (or staged changes by default), renders a system
# prompt from the template, and launches the configured agent.
# Each invocation starts a fresh session.
#
# Usage: _git_chat [REF1 [REF2]] [--staged] [-d <DESCRIPTION>] [-- AGENT_OPTIONS]
_git_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_chat_help
		return 0
		;;
	esac

	local args=() passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_git_ai_source_dir/templates/git_chat.tmpl"

	local ref1="" ref2="" staged="" description=""
	_parse_chat_args_git ref1 ref2 staged description "${args[@]}"

	local ctx_dir
	_create_context_dir ctx_dir

	# shellcheck disable=SC2064
	trap "rm -rf '$ctx_dir'" EXIT

	local diff_refs="" git_branch=""
	_prepare_diff_context "$ref1" "$ref2" "$staged" "$ctx_dir" \
		diff_refs git_branch || return 1

	local focus=""
	if [[ -n "$description" ]]; then
		focus="<focus>$description</focus>"
	fi

	local prompt
	prompt=$(
		GIT_DIFF_REFS="$diff_refs" \
			GIT_BRANCH="$git_branch" \
			GIT_DIFF_FOCUS="$focus" \
			GIT_AI_SESSION_DIR="$ctx_dir" \
			"$_git_ai_source_dir/scripts/git_cmd.sh" render "$template_file"
	)

	_cmd_chat "$prompt" "${passthrough[@]}"
}
