#!/usr/bin/env bats

# Unit and integration tests for git ai commit
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_commit.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _git_ai_source_dir="$REPO_ROOT"

	# Mock external commands not under test
	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() { echo ""; }
	export -f gum git

	# Source git_commit.sh inside a subshell and import only the function
	# definitions.  This prevents the `set -euo pipefail` at the top of
	# git_commit.sh from leaking into the bats test runner, which would
	# cause pipefail-triggered deadlocks when a test assertion fails.
	# shellcheck disable=SC2155
	eval "$(
		export _git_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/git_cmd.sh
		source "$REPO_ROOT/scripts/git_cmd.sh"
		# shellcheck source=../scripts/git_commit.sh
		source "$REPO_ROOT/scripts/git_commit.sh"
		declare -f _parse_commit_args _show_commit_help _git_commit _split_on_separator
	)"
}

@test "_parse_commit_args: sets description from -d flag" {
	local description=""
	_parse_commit_args description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_commit_args: sets description from --description flag" {
	local description=""
	_parse_commit_args description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "_parse_commit_args: sets description from --description=value" {
	local description=""
	_parse_commit_args description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

@test "_parse_commit_args: accepts empty string for -d" {
	local description=""
	_parse_commit_args description -d ""

	[[ -z "$description" ]]
}

@test "_parse_commit_args: preserves special characters in description" {
	local description=""
	_parse_commit_args description -d "fix: handle \$HOME and 'quotes' & <html>"

	[[ "$description" == 'fix: handle $HOME and '"'"'quotes'"'"' & <html>' ]]
}

@test "_parse_commit_args: preserves long description verbatim" {
	local long_desc
	long_desc="$(printf 'word%.0s ' {1..100})"
	local description=""
	_parse_commit_args description -d "$long_desc"

	[[ "$description" == "$long_desc" ]]
}

@test "_parse_commit_args: defaults description to empty when no flags given" {
	local description=""
	_parse_commit_args description

	[[ -z "$description" ]]
}

@test "_parse_commit_args: last value wins when -d and --description both given" {
	local description=""
	_parse_commit_args description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_commit_args: returns error when -d has no value" {
	local description=""
	run _parse_commit_args description -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_commit_args: returns error when --description has no value" {
	local description=""
	run _parse_commit_args description --description

	[[ "$status" -eq 1 ]]
}

@test "_parse_commit_args: returns error with hint for unknown flags" {
	local description=""
	run _parse_commit_args description --signoff

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to git commit"* ]]
}
