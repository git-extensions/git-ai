#!/usr/bin/env bats

# Unit tests for git ai chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _git_ai_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() { echo ""; }
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _git_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/git_cmd.sh
		source "$REPO_ROOT/scripts/git_cmd.sh"
		# shellcheck source=../scripts/git_chat.sh
		source "$REPO_ROOT/scripts/git_chat.sh"
		declare -f _parse_chat_args_git _show_chat_help _git_chat \
			_prepare_diff_context _create_context_dir _save_context_file \
			_split_on_separator _cmd_render _cmd_chat _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_chat_args_git
# ---------------------------------------------------------------------------

@test "_parse_chat_args_git: no args leaves all empty" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc

	[[ -z "$ref1" ]]
	[[ -z "$ref2" ]]
	[[ -z "$staged" ]]
	[[ -z "$desc" ]]
}

@test "_parse_chat_args_git: sets ref1 from first positional arg" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc main

	[[ "$ref1" == "main" ]]
	[[ -z "$ref2" ]]
}

@test "_parse_chat_args_git: sets ref1 and ref2 from two positional args" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc HEAD~3 HEAD

	[[ "$ref1" == "HEAD~3" ]]
	[[ "$ref2" == "HEAD" ]]
}

@test "_parse_chat_args_git: accepts range notation as ref1" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc "HEAD~3..HEAD"

	[[ "$ref1" == "HEAD~3..HEAD" ]]
}

@test "_parse_chat_args_git: sets staged flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc --staged

	[[ "$staged" == "1" ]]
}

@test "_parse_chat_args_git: sets description from -d flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc -d "security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: sets description from --description flag" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc --description "security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: sets description from --description=value" {
	local ref1="" ref2="" staged="" desc=""
	_parse_chat_args_git ref1 ref2 staged desc --description="security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: returns error for unknown flag" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_chat_args_git ref1 ref2 staged desc --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_chat_args_git: returns error for third positional arg" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_chat_args_git ref1 ref2 staged desc HEAD~3 HEAD extra

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'extra'"* ]]
}

@test "_parse_chat_args_git: returns error when -d has no value" {
	local ref1="" ref2="" staged="" desc=""
	run _parse_chat_args_git ref1 ref2 staged desc -d

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _show_chat_help
# ---------------------------------------------------------------------------

@test "_show_chat_help: prints help text" {
	run _show_chat_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai chat"* ]]
	[[ "$output" == *"--staged"* ]]
	[[ "$output" == *"-d"* ]]
}

# ---------------------------------------------------------------------------
# _git_chat integration tests
# ---------------------------------------------------------------------------

_setup_chat_mocks() {
	git() {
		case "$*" in
		"diff --staged") echo "diff --git a/file.txt b/file.txt" ;;
		"diff --staged --stat") echo " file.txt | 1 +" ;;
		"rev-parse HEAD") echo "abc1234" ;;
		"rev-parse --abbrev-ref HEAD") echo "main" ;;
		*) echo "" ;;
		esac
	}
	export -f git

	gum() {
		case "$1" in
		log) ;;
		esac
	}
	export -f gum
}

@test "_git_chat: shows help with --help flag" {
	run _git_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai chat"* ]]
}

@test "_git_chat: calls _cmd_chat with rendered system prompt" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT_LEN:%d\n' "${#1}"
	}

	run _git_chat

	[[ "$status" -eq 0 ]]
	local prompt_len
	prompt_len=$(printf '%s' "$output" | grep 'PROMPT_LEN:' | cut -d: -f2)
	[[ "$prompt_len" -gt 0 ]]
}

@test "_git_chat: passes description as focus in prompt" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT:%s\n' "$1"
	}

	run _git_chat -d "security focus"

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"security focus"* ]]
}

@test "_git_chat: forwards passthrough args to _cmd_chat" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _git_chat -- --model sonnet --verbose

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--model sonnet --verbose"* ]]
}

@test "_git_chat: errors when diff is empty" {
	git() { echo ""; }
	export -f git

	run _git_chat

	[[ "$status" -eq 1 ]]
}
