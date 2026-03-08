#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Explain help function
#
# Displays help information for the explain command
# including usage examples and available options.
_show_explain_help() {
	cat <<'EOF'
git ai explain - Explain git changes in plain language

USAGE:
    git ai explain [REF1 [REF2]] [--staged] [-d <DESCRIPTION>]

DESCRIPTION:
    Generates a plain-language explanation of git changes and prints it
    to stdout.

    No args / --staged  → git diff --staged (default)
    Single ref          → git diff <ref>...HEAD
    Range (ref1..ref2)  → git diff <ref1>..<ref2>
    Two refs            → git diff <ref1> <ref2>

FLAGS:
    -d, --description <TEXT>    Additional context for the explanation

EXAMPLES:
    git ai explain                          # explain staged changes
    git ai explain --staged                 # same as above
    git ai explain HEAD~3                   # changes since HEAD~3
    git ai explain HEAD~3..HEAD             # explicit range
    git ai explain main                     # changes since main
    git ai explain main feature-branch      # diff between two refs
    git ai explain -d "focus on auth"       # with extra context
EOF
}

# Parse explain arguments
#
# Extracts up to two optional ref positional args, --staged flag,
# and -d/--description value. Unknown flags produce an error.
#
# Usage: _parse_explain_args ref1_ref ref2_ref staged_ref desc_ref [args...]
_parse_explain_args() {
	local -n _pea_ref1="$1"
	local -n _pea_ref2="$2"
	local -n _pea_staged="$3"
	local -n _pea_desc="$4"
	shift 4

	local _pea_raw=("$@")
	local _pea_skip=false
	local _pea_i=0

	while [[ $_pea_i -lt ${#_pea_raw[@]} ]]; do
		if [[ "$_pea_skip" = true ]]; then
			_pea_skip=false
			((++_pea_i))
			continue
		fi

		case "${_pea_raw[$_pea_i]}" in
		--staged)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pea_staged=1
			;;
		--description | -d)
			if ((_pea_i + 1 >= ${#_pea_raw[@]})); then
				gum log --level error "${_pea_raw[$_pea_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_pea_desc="${_pea_raw[$((_pea_i + 1))]}"
			_pea_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pea_desc="${_pea_raw[$_pea_i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${_pea_raw[$_pea_i]}'"
			return 1
			;;
		*)
			if [[ -z "$_pea_ref1" ]]; then
				_pea_ref1="${_pea_raw[$_pea_i]}"
			elif [[ -z "$_pea_ref2" ]]; then
				_pea_ref2="${_pea_raw[$_pea_i]}"
			else
				gum log --level error "unexpected argument '${_pea_raw[$_pea_i]}'"
				return 1
			fi
			;;
		esac
		((++_pea_i))
	done
}

# Main explain command implementation
#
# Generates a plain-language explanation of git changes using AI.
# Builds a diff based on the provided refs (or staged changes by default),
# renders a prompt template, sends it to the AI provider, and prints the result.
#
# Usage: _git_explain [REF1 [REF2]] [--staged] [-d <DESCRIPTION>]
_git_explain() {
	case "${1:-}" in
	--help | -h | help)
		_show_explain_help
		return 0
		;;
	esac

	local ref1="" ref2="" staged="" description=""
	_parse_explain_args ref1 ref2 staged description "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_git_ai_source_dir/templates/git_explain.tmpl"

	local ctx_dir
	_create_context_dir ctx_dir

	# shellcheck disable=SC2064
	trap "rm -rf '$ctx_dir'" EXIT

	local diff_refs="" git_branch=""
	_prepare_diff_context "$ref1" "$ref2" "$staged" "$ctx_dir" \
		diff_refs git_branch || return 1

	local agent_model
	agent_model=$(git config ai.explain.model 2>/dev/null || true)

	local description_context=""
	if [[ -n "$description" ]]; then
		description_context="<description>$description</description>"
	fi

	local explain_output
	explain_output=$(
		gum spin --title "Generating explanation..." -- \
			"$_git_ai_source_dir/scripts/git_cmd.sh" ask "$agent_model" < <(
				GIT_DIFF_FILE="$ctx_dir/diff.patch" \
					GIT_DIFF_STAT_FILE="$ctx_dir/diff_stat.txt" \
					GIT_COMMITS_FILE="$ctx_dir/commits.txt" \
					GIT_DIFF_REFS="$diff_refs" \
					GIT_BRANCH="$git_branch" \
					GIT_EXPLAIN_DESCRIPTION="$description_context" \
					"$_git_ai_source_dir/scripts/git_cmd.sh" render "$template_file"
			)
	)

	if [[ -z "$explain_output" ]]; then
		gum log --level error "Failed to generate explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$explain_output"
}
