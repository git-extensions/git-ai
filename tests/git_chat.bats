#!/usr/bin/env bats

# Unit tests for git ai chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _git_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	mkdir -p "$BATS_TEST_TMPDIR/.git"
	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		*) echo "" ;;
		esac
	}
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _git_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/git_cmd.sh
		source "$REPO_ROOT/scripts/git_cmd.sh"
		# shellcheck source=../scripts/git_chat.sh
		source "$REPO_ROOT/scripts/git_chat.sh"
		declare -f _parse_chat_args_git _session_slug _show_chat_help _git_chat \
			_prepare_diff_context _validate_chat_passthrough _resolve_chat_session \
			_resolve_context_dir _create_context_dir _save_context_file \
			_git_repo_path _git_main_worktree_path _git_session_base_dir \
			_split_on_separator _cmd_render _cmd_chat _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_chat_args_git
# ---------------------------------------------------------------------------

@test "_parse_chat_args_git: no args leaves all empty" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session

	[[ -z "$ref1" ]]
	[[ -z "$ref2" ]]
	[[ -z "$staged" ]]
	[[ -z "$desc" ]]
	[[ -z "$new_session" ]]
}

@test "_parse_chat_args_git: sets ref1 from first positional arg" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session main

	[[ "$ref1" == "main" ]]
	[[ -z "$ref2" ]]
}

@test "_parse_chat_args_git: sets ref1 and ref2 from two positional args" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session HEAD~3 HEAD

	[[ "$ref1" == "HEAD~3" ]]
	[[ "$ref2" == "HEAD" ]]
}

@test "_parse_chat_args_git: accepts range notation as ref1" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session "HEAD~3..HEAD"

	[[ "$ref1" == "HEAD~3..HEAD" ]]
}

@test "_parse_chat_args_git: sets staged flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session --staged

	[[ "$staged" == "1" ]]
}

@test "_parse_chat_args_git: sets description from -d flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session -d "security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: sets description from --description flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session --description "security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: sets description from --description=value" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session --description="security focus"

	[[ "$desc" == "security focus" ]]
}

@test "_parse_chat_args_git: sets new_session from -n flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session -n

	[[ "$new_session" == "1" ]]
}

@test "_parse_chat_args_git: sets new_session from --new-session flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session --new-session

	[[ "$new_session" == "1" ]]
}

@test "_parse_chat_args_git: new_session defaults to empty" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	_parse_chat_args_git ref1 ref2 staged desc new_session main

	[[ -z "$new_session" ]]
}

@test "_parse_chat_args_git: returns error for unknown flag" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	run _parse_chat_args_git ref1 ref2 staged desc new_session --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_chat_args_git: returns error for third positional arg" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	run _parse_chat_args_git ref1 ref2 staged desc new_session HEAD~3 HEAD extra

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'extra'"* ]]
}

@test "_parse_chat_args_git: returns error when -d has no value" {
	local ref1="" ref2="" staged="" desc="" new_session=""
	run _parse_chat_args_git ref1 ref2 staged desc new_session -d

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _session_slug
# ---------------------------------------------------------------------------

@test "_session_slug: no refs returns staged" {
	local slug
	slug=$(_session_slug "" "" "")

	[[ "$slug" == "staged" ]]
}

@test "_session_slug: --staged flag returns staged" {
	local slug
	slug=$(_session_slug "" "" "1")

	[[ "$slug" == "staged" ]]
}

@test "_session_slug: single ref appends ..HEAD" {
	local slug
	slug=$(_session_slug "main" "" "")

	[[ "$slug" == "main-HEAD" ]]
}

@test "_session_slug: branch name with slash is sanitized" {
	local slug
	slug=$(_session_slug "feature/my-branch" "" "")

	[[ "$slug" == "feature-my-branch-HEAD" ]]
}

@test "_session_slug: range notation ref1 is sanitized" {
	local slug
	slug=$(_session_slug "HEAD~3..HEAD" "" "")

	[[ "$slug" == "HEAD-3-HEAD-HEAD" ]]
}

@test "_session_slug: two refs produces ref1..ref2 slug" {
	local slug
	slug=$(_session_slug "HEAD~3" "HEAD" "")

	[[ "$slug" == "HEAD-3-HEAD" ]]
}

@test "_session_slug: tilde in ref is replaced with hyphen" {
	local slug
	slug=$(_session_slug "HEAD~5" "" "")

	[[ "$slug" == "HEAD-5-HEAD" ]]
}

# ---------------------------------------------------------------------------
# _show_chat_help
# ---------------------------------------------------------------------------

@test "_show_chat_help: prints help text" {
	run _show_chat_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai chat"* ]]
	[[ "$output" == *"--staged"* ]]
	[[ "$output" == *"-n"* ]]
	[[ "$output" == *"--new-session"* ]]
}

# ---------------------------------------------------------------------------
# _git_chat integration tests
# ---------------------------------------------------------------------------

_setup_chat_mocks() {
	git() {
		case "$*" in
		"diff --staged") echo "diff --git a/file.txt b/file.txt" ;;
		"diff --staged --stat") echo " file.txt | 1 +" ;;
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
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

@test "_git_chat: calls _cmd_chat with --session-id on first call" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _git_chat

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]
}

@test "_git_chat: passes system prompt on new session" {
	_setup_chat_mocks

	local captured_prompt=""
	_cmd_chat() {
		captured_prompt="$1"
		printf 'PROMPT_LEN:%d\n' "${#1}"
	}

	run _git_chat

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PROMPT_LEN:"* ]]
	# Prompt length should be > 0 for new session
	local prompt_len
	prompt_len=$(printf '%s' "$output" | grep 'PROMPT_LEN:' | cut -d: -f2)
	[[ "$prompt_len" -gt 0 ]]
}

@test "_git_chat: resumes previous session on second call" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	# First call creates session
	run _git_chat
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Second call should resume
	run _git_chat
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--resume"* ]]
}

@test "_git_chat: empty prompt on resumed session" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT_LEN:%d\n' "${#1}"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	# Establish a session
	run _git_chat
	[[ "$status" -eq 0 ]]

	# Second call — prompt should be empty
	run _git_chat
	[[ "$status" -eq 0 ]]
	local prompt_len
	prompt_len=$(printf '%s' "$output" | grep 'PROMPT_LEN:' | cut -d: -f2)
	[[ "$prompt_len" -eq 0 ]]
}

@test "_git_chat: -n forces new session after existing one" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'ARGS:%s\n' "$*"
	}

	# Establish session
	run _git_chat
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Force new session
	run _git_chat -n
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]
}

@test "_git_chat: staged and branch-scoped sessions are independent" {
	_setup_chat_mocks

	git() {
		case "$*" in
		"diff --staged") echo "diff --git a/staged.txt b/staged.txt" ;;
		"diff --staged --stat") echo " staged.txt | 1 +" ;;
		"diff main...HEAD") echo "diff --git a/branch.txt b/branch.txt" ;;
		"diff main...HEAD --stat") echo " branch.txt | 1 +" ;;
		"log --oneline main..HEAD") echo "abc1234 commit" ;;
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		"rev-parse HEAD") echo "abc1234" ;;
		"rev-parse --abbrev-ref HEAD") echo "main" ;;
		*) echo "" ;;
		esac
	}
	export -f git

	_cmd_chat() {
		printf 'ARGS:%s\n' "$*"
	}

	run _git_chat
	local staged_output="$output"

	run _git_chat main
	local branch_output="$output"

	# Extract UUIDs from both outputs
	local staged_uuid branch_uuid
	staged_uuid=$(printf '%s' "$staged_output" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
	branch_uuid=$(printf '%s' "$branch_output" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

	[[ "$staged_uuid" != "$branch_uuid" ]]
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

@test "_git_chat: rejects managed flags in passthrough" {
	run _git_chat -- --session-id custom

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--session-id is managed by git-ai"* ]]
}

@test "_git_chat: errors when diff is empty" {
	git() {
		case "$*" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		*) echo "" ;;
		esac
	}
	export -f git

	run _git_chat

	[[ "$status" -eq 1 ]]
}
