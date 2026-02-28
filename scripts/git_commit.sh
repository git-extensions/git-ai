#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Commit help function
#
# Displays help information for the commit command
# including usage examples and available options.
_show_commit_help() {
	cat <<'EOF'
git ai commit - Create commits with AI-generated messages

USAGE:
    git ai commit [-d <DESCRIPTION>] [-- GIT_COMMIT_OPTIONS]

DESCRIPTION:
    Generates a conventional commit message from staged changes using AI,
    then creates the commit. Options after -- are passed to git commit.

FLAGS:
    -d, --description <TEXT>    Additional context for AI commit message generation

EXAMPLES:
    git ai commit                                        # Generate message and commit
    git ai commit -d "focus on security improvements"   # With additional context
    git ai commit -- --signoff                           # Commit with sign-off
    git ai commit -- --no-verify                         # Skip pre-commit hooks

SEE ALSO:
    git commit --help    # Full list of git commit options
EOF
}

# Parse commit arguments (before -- separator)
#
# Extracts the optional -d/--description value. Unknown flags produce
# an error with a hint to use -- for git commit options.
#
# Example: _parse_commit_args desc -d "context"
_parse_commit_args() {
	local -n gh_commit_description_ref="$1"
	shift

	local raw_args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${raw_args[$i]}" in
		--description | -d)
			if (( i + 1 >= ${#raw_args[@]} )); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_commit_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_commit_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to git commit)"
			return 1
			;;
		*)
			gum log --level error "unexpected argument '${raw_args[$i]}'"
			return 1
			;;
		esac
		((++i))
	done
}

# Main commit command implementation
#
# Creates a git commit with an AI-generated message based on staged changes.
# Renders a prompt template with the staged diff and branch context,
# sends it to the AI provider, and commits with the response.
#
# Usage: _git_commit [-d <DESCRIPTION>] [-- OPTIONS]
_git_commit() {
	case "${1:-}" in
	--help | -h | help)
		_show_commit_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_git_ai_source_dir/templates/git_commit.tmpl"

	local gh_commit_description=""
	_parse_commit_args gh_commit_description "${ai_args[@]}"

	# Gather git context
	local git_diff_staged
	git_diff_staged=$(git diff --staged)

	# Check if there are staged changes
	if [[ -z "$git_diff_staged" ]]; then
		gum log --level error "No staged changes found"
		gum log --level info "Stage your changes with 'git add' first"
		return 1
	fi

	local git_diff_staged_stat
	git_diff_staged_stat=$(git diff --staged --stat)

	local git_branch
	git_branch=$(git rev-parse --abbrev-ref HEAD)

	local git_log_oneline
	git_log_oneline=$(git log --oneline -5 2>/dev/null | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(git config ai.commit.model 2>/dev/null || true)

	# Format description as context block if provided
	local gh_commit_description_context=""
	if [[ -n "$gh_commit_description" ]]; then
		gh_commit_description_context="<description>$gh_commit_description</description>"
	fi

	local git_commit_message
	# Generate commit message using assistant run
	git_commit_message=$(
		gum spin --title "Generating Git commit message..." -- \
			"$_git_ai_source_dir/scripts/git_cmd.sh" ask "$agent_model" < <(
				GIT_DIFF_STAGED="$git_diff_staged" GIT_DIFF_STAGED_STAT="$git_diff_staged_stat" GIT_BRANCH="$git_branch" GIT_COMMITS="$git_log_oneline" GH_COMMIT_DESCRIPTION="$gh_commit_description_context" \
					"$_git_ai_source_dir/scripts/git_cmd.sh" render "$template_file"
			)
	)

	# Validate we got a commit message
	if [[ -z "$git_commit_message" ]]; then
		gum log --level error "Failed to generate commit message"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$git_commit_message" "${passthrough[@]}"
}
