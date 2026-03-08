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
    git ai chat [REF1 [REF2]] [--staged] [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]

DESCRIPTION:
    Starts or resumes an interactive AI session scoped to a git diff.
    Sessions are persisted under .git/sessions/chat/<slug>/ and resume
    automatically on subsequent invocations with the same refs.

    No args / --staged  → git diff --staged (default)
    Single ref          → git diff <ref>...HEAD
    Range (ref1..ref2)  → git diff <ref1>..<ref2>
    Two refs            → git diff <ref1> <ref2>

FLAGS:
    -d, --description <TEXT>    Extra context or focus for the session
    -n, --new-session           Force a new session instead of resuming
    -- AGENT_OPTIONS            Options passed directly to the agent binary

EXAMPLES:
    git ai chat                             # chat about staged changes
    git ai chat --staged                    # same as above
    git ai chat HEAD~3                      # chat about changes since HEAD~3
    git ai chat main                        # chat about changes since main
    git ai chat HEAD~3..HEAD                # explicit range
    git ai chat pr-122-branch               # chat about branch divergence
    git ai chat -d "any security issues?"   # with extra focus
    git ai chat -n                          # force new session
    git ai chat -- --model sonnet           # pass model to agent
EOF
}

# Parse chat arguments (before -- separator)
#
# Extracts up to two optional ref positional args, --staged flag,
# -d/--description value, and -n/--new-session flag.
# Unknown flags produce an error.
#
# Usage: _parse_chat_args_git ref1_ref ref2_ref staged_ref desc_ref new_session_ref [args...]
_parse_chat_args_git() {
	local -n _pcag_ref1="$1"
	local -n _pcag_ref2="$2"
	local -n _pcag_staged="$3"
	local -n _pcag_desc="$4"
	local -n _pcag_new_session="$5"
	shift 5

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
		--new-session | -n)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pcag_new_session=1
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

# Compute a filesystem-safe session slug from diff refs
#
# Derives a short identifier used as the session directory name so that
# each distinct diff scope gets its own resumable chat session.
#
# Usage: slug=$(_session_slug ref1 ref2 staged)
_session_slug() {
	local ref1="$1" ref2="$2" staged="$3"
	local slug

	if [[ -n "$ref2" ]]; then
		slug="$ref1..$ref2"
	elif [[ -n "$ref1" ]]; then
		slug="$ref1..HEAD"
	else
		slug="staged"
	fi

	# Sanitize: replace non-alphanumeric/dash/underscore chars with hyphens,
	# then squeeze consecutive hyphens and strip leading/trailing hyphens.
	printf '%s' "$slug" | tr -c 'a-zA-Z0-9_-' '-' | tr -s '-' | sed 's/^-//; s/-$//'
}

# Main chat command implementation
#
# Starts or resumes an interactive AI session scoped to a git diff.
# Builds diff context from the provided refs (or staged changes by default),
# then calls the configured agent with a rendered system prompt on new sessions
# or resumes an existing session silently.
#
# Usage: _git_chat [REF1 [REF2]] [--staged] [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]
_git_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_chat_help
		return 0
		;;
	esac

	local args=() passthrough=()
	_split_on_separator args passthrough "$@"
	_validate_chat_passthrough passthrough || return 1

	local template_file
	# shellcheck disable=SC2154
	template_file="$_git_ai_source_dir/templates/git_chat.tmpl"

	local ref1="" ref2="" staged="" description="" new_session=""
	_parse_chat_args_git ref1 ref2 staged description new_session "${args[@]}"

	local slug
	slug=$(_session_slug "$ref1" "$ref2" "$staged")

	local session_dir
	_resolve_context_dir "chat" "chat/$slug" session_dir || return 1

	local diff_file="" diff_stat="" diff_refs="" diff_commits="" git_branch=""
	_prepare_diff_context "$ref1" "$ref2" "$staged" "$session_dir" \
		diff_file diff_stat diff_refs diff_commits git_branch || return 1

	local focus=""
	if [[ -n "$description" ]]; then
		focus="<focus>$description</focus>"
	fi

	local is_new_chat="" session_args=()
	_resolve_chat_session "$session_dir" "$new_session" is_new_chat session_args || return 1

	local prompt=""
	if [[ -n "$is_new_chat" ]]; then
		prompt=$(
			GIT_DIFF_REFS="$diff_refs" \
				GIT_BRANCH="$git_branch" \
				GIT_DIFF_FOCUS="$focus" \
				GIT_AI_SESSION_DIR="$session_dir" \
				"$_git_ai_source_dir/scripts/git_cmd.sh" render "$template_file"
		)
	fi

	_cmd_chat "$prompt" "${session_args[@]}" "${passthrough[@]}"
}
