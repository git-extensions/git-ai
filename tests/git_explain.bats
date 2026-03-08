#!/usr/bin/env bats

# Unit tests for git ai explain arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_explain.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _git_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	mkdir -p "$BATS_TEST_TMPDIR/.git"
	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() { echo ""; }
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _git_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/git_cmd.sh
		source "$REPO_ROOT/scripts/git_cmd.sh"
		# shellcheck source=../scripts/git_explain.sh
		source "$REPO_ROOT/scripts/git_explain.sh"
		declare -f _parse_explain_args _show_explain_help _git_explain \
			_prepare_diff_context _create_context_dir _save_context_file \
			_split_on_separator _cmd_render _cmd_ask _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_explain_args
# ---------------------------------------------------------------------------

@test "_parse_explain_args: no args leaves all refs empty" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc

	[[ -z "$ref1" ]]
	[[ -z "$ref2" ]]
	[[ -z "$staged" ]]
	[[ -z "$desc" ]]
}

@test "_parse_explain_args: sets ref1 from first positional arg" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc HEAD~3

	[[ "$ref1" == "HEAD~3" ]]
	[[ -z "$ref2" ]]
}

@test "_parse_explain_args: sets ref1 and ref2 from two positional args" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc HEAD~3 HEAD

	[[ "$ref1" == "HEAD~3" ]]
	[[ "$ref2" == "HEAD" ]]
}

@test "_parse_explain_args: accepts range notation as ref1" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc "HEAD~3..HEAD"

	[[ "$ref1" == "HEAD~3..HEAD" ]]
	[[ -z "$ref2" ]]
}

@test "_parse_explain_args: sets staged flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc --staged

	[[ "$staged" == "1" ]]
}

@test "_parse_explain_args: sets description from -d flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc -d "focus on auth"

	[[ "$desc" == "focus on auth" ]]
}

@test "_parse_explain_args: sets description from --description flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc --description "focus on auth"

	[[ "$desc" == "focus on auth" ]]
}

@test "_parse_explain_args: sets description from --description=value" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc --description="focus on auth"

	[[ "$desc" == "focus on auth" ]]
}

@test "_parse_explain_args: parses ref1 and description together" {
	local ref1="" ref2="" staged="" desc=""
	_parse_explain_args ref1 ref2 staged desc main -d "security focus"

	[[ "$ref1" == "main" ]]
	[[ "$desc" == "security focus" ]]
}

@test "_parse_explain_args: returns error for unknown flag" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_explain_args ref1 ref2 staged desc --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_explain_args: returns error for third positional arg" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_explain_args ref1 ref2 staged desc HEAD~3 HEAD extra

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'extra'"* ]]
}

@test "_parse_explain_args: returns error when -d has no value" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_explain_args ref1 ref2 staged desc -d

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _show_explain_help
# ---------------------------------------------------------------------------

@test "_show_explain_help: prints help text" {
	run _show_explain_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai explain"* ]]
	[[ "$output" == *"--staged"* ]]
	[[ "$output" == *"-d"* ]]
}

# ---------------------------------------------------------------------------
# _git_explain integration tests
# ---------------------------------------------------------------------------

_setup_explain_mocks() {
	git() {
		case "$*" in
		"diff --staged") echo "diff --git a/file.txt b/file.txt" ;;
		"diff --staged --stat") echo " file.txt | 1 +" ;;
		"diff HEAD~3...HEAD") echo "diff --git a/file.txt b/file.txt" ;;
		"diff HEAD~3...HEAD --stat") echo " file.txt | 1 +" ;;
		"log --oneline HEAD~3..HEAD") echo "abc1234 first commit" ;;
		"rev-parse HEAD") echo "abc1234" ;;
		"rev-parse --abbrev-ref HEAD") echo "main" ;;
		*) echo "" ;;
		esac
	}
	export -f git

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/git_cmd.sh)
				printf '## Summary\n\nThis changes things.\n'
				;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_git_explain: prints explanation to stdout for staged changes" {
	_setup_explain_mocks

	run _git_explain

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Summary"* ]]
	[[ "$output" == *"This changes things."* ]]
}

@test "_git_explain: shows help with --help flag" {
	run _git_explain --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai explain"* ]]
}

@test "_git_explain: errors when diff is empty" {
	git() { echo ""; }
	export -f git

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@"
			;;
		log) ;;
		esac
	}
	export -f gum

	run _git_explain

	[[ "$status" -eq 1 ]]
}

@test "_git_explain: errors when AI output is empty" {
	_setup_explain_mocks

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/git_cmd.sh) ;; # return empty
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum

	run _git_explain

	[[ "$status" -eq 1 ]]
}
