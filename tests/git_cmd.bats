#!/usr/bin/env bats

# Unit tests for utility functions in git_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_cmd.bats

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
		printf '_git_cmd_dir=%q\n' "$_git_cmd_dir"
		declare -f _split_on_separator _cmd_render \
			_git_repo_path _git_main_worktree_path _git_session_base_dir \
			_trust_workspace _resolve_chat_session \
			_create_context_dir _resolve_context_dir _save_context_file \
			_validate_chat_passthrough
	)"
}

# ---------------------------------------------------------------------------
# _split_on_separator
# ---------------------------------------------------------------------------

@test "_split_on_separator: places all args in before when no -- present" {
	local before=() after=()
	_split_on_separator before after -d "desc" --flag

	[[ ${#before[@]} -eq 3 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ "${before[2]}" == "--flag" ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: splits args on --" {
	local before=() after=()
	_split_on_separator before after -d "desc" -- --signoff --no-verify

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 2 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--no-verify" ]]
}

@test "_split_on_separator: handles empty before when -- is first arg" {
	local before=() after=()
	_split_on_separator before after -- --signoff

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 1 ]]
}

@test "_split_on_separator: returns two empty arrays for no arguments" {
	local before=() after=()
	_split_on_separator before after

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _cmd_render with _FILE fallback
# ---------------------------------------------------------------------------

@test "_cmd_render: substitutes env vars in template" {
	local tmpdir="$BATS_TMPDIR/render-test-$$"
	mkdir -p "$tmpdir"
	printf 'Hello ${MY_NAME}, welcome to ${MY_PLACE}.\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_NAME="Alice" MY_PLACE="Wonderland" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Hello Alice, welcome to Wonderland."* ]]
}

@test "_cmd_render: leaves unset vars as empty strings" {
	local tmpdir="$BATS_TMPDIR/render-unset-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${UNSET_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(_cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: does not re-expand vars inside substituted values" {
	local tmpdir="$BATS_TMPDIR/render-safe-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff: ${GIT_DIFF}\n' >"$tmpdir/test.tmpl"

	local output
	output=$(GIT_DIFF='contains ${SECRET} token' _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *'contains ${SECRET} token'* ]]
}

@test "_cmd_render: returns error for missing template file" {
	run _cmd_render "/nonexistent/template.tmpl"

	[[ "$status" -eq 1 ]]
}

@test "_cmd_render: reads file content from VAR_FILE env var" {
	local tmpdir="$BATS_TMPDIR/render-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GIT_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'line one\nline two\nline three' >"$tmpdir/diff.patch"

	local output
	output=$(GIT_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "_cmd_render: direct env var takes priority over _FILE" {
	local tmpdir="$BATS_TMPDIR/render-priority-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: ${MY_VAR}\n' >"$tmpdir/test.tmpl"
	printf 'from file' >"$tmpdir/value.txt"

	local output
	output=$(MY_VAR="from env" MY_VAR_FILE="$tmpdir/value.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: from env"* ]]
	[[ "$output" != *"from file"* ]]
}

@test "_cmd_render: nonexistent _FILE path produces empty string" {
	local tmpdir="$BATS_TMPDIR/render-missing-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${MY_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_VAR_FILE="/nonexistent/file.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: patterns in file content not re-expanded" {
	local tmpdir="$BATS_TMPDIR/render-safety-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GIT_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'contains ${SECRET_TOKEN} and ${OTHER} patterns' >"$tmpdir/diff.patch"

	local output
	output=$(GIT_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *'contains ${SECRET_TOKEN} and ${OTHER} patterns'* ]]
}

# ---------------------------------------------------------------------------
# _git_repo_path
# ---------------------------------------------------------------------------

@test "_git_repo_path: sets nameref when git rev-parse succeeds" {
	git() { echo "/home/user/myrepo"; }
	export -f git

	local dir=""
	_git_repo_path dir

	[[ "$dir" == "/home/user/myrepo" ]]
}

@test "_git_repo_path: returns error when git rev-parse returns empty" {
	git() { :; }
	export -f git

	local dir=""
	run _git_repo_path dir

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _git_session_base_dir
# ---------------------------------------------------------------------------

@test "_git_session_base_dir: returns .git/sessions under provided root" {
	local result
	result=$(_git_session_base_dir "/home/user/myrepo")

	[[ "$result" == "/home/user/myrepo/.git/sessions" ]]
}

@test "_git_session_base_dir: uses the provided path verbatim" {
	local result
	result=$(_git_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "$BATS_TEST_TMPDIR/.git/sessions" ]]
}

# ---------------------------------------------------------------------------
# _trust_workspace
# ---------------------------------------------------------------------------

@test "_trust_workspace: creates ~/.claude.json when absent" {
	rm -f "$HOME/.claude.json"

	_trust_workspace "/tmp/test-workspace"

	[[ -f "$HOME/.claude.json" ]]
	local accepted
	accepted=$(jq -r '.projects["/tmp/test-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$accepted" == "true" ]]
}

@test "_trust_workspace: merges into existing ~/.claude.json" {
	printf '%s\n' '{"existingKey": "existingValue"}' >"$HOME/.claude.json"

	_trust_workspace "/tmp/new-workspace"

	local existing
	existing=$(jq -r '.existingKey' "$HOME/.claude.json")
	[[ "$existing" == "existingValue" ]]

	local accepted
	accepted=$(jq -r '.projects["/tmp/new-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$accepted" == "true" ]]
}

@test "_trust_workspace: preserves existing workspace entries" {
	jq -n '{projects: {"/tmp/other": {hasTrustDialogAccepted: true, customSetting: "keep"}}}' >"$HOME/.claude.json"

	_trust_workspace "/tmp/new-workspace"

	local other_accepted
	other_accepted=$(jq -r '.projects["/tmp/other"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$other_accepted" == "true" ]]

	local custom
	custom=$(jq -r '.projects["/tmp/other"].customSetting' "$HOME/.claude.json")
	[[ "$custom" == "keep" ]]

	local new_accepted
	new_accepted=$(jq -r '.projects["/tmp/new-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$new_accepted" == "true" ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: first call returns --session-id and a UUID" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-1"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ "$is_new" == "1" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--session-id" ]]
	[[ -n "${args[1]}" ]]
}

@test "_resolve_chat_session: creates session.id file on first call" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-2"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ -f "$session_dir/session.id" ]]
}

@test "_resolve_chat_session: second call returns --resume with same UUID" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-3"
	mkdir -p "$session_dir"

	local is_new1="" args1=()
	_resolve_chat_session "$session_dir" "" is_new1 args1
	local first_uuid="${args1[1]}"

	local is_new2="" args2=()
	_resolve_chat_session "$session_dir" "" is_new2 args2

	[[ -z "$is_new2" ]]
	[[ "${args2[0]}" == "--resume" ]]
	[[ "${args2[1]}" == "$first_uuid" ]]
}

@test "_resolve_chat_session: --new-session deletes session file and returns --session-id" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-4"
	mkdir -p "$session_dir"

	local is_new1="" args1=()
	_resolve_chat_session "$session_dir" "" is_new1 args1

	local is_new2="" args2=()
	_resolve_chat_session "$session_dir" "1" is_new2 args2

	[[ "$is_new2" == "1" ]]
	[[ "${args2[0]}" == "--session-id" ]]
}

@test "_resolve_chat_session: UUID is lowercase" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-5"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ "${args[1]}" =~ ^[0-9a-f-]+$ ]]
}

@test "_resolve_chat_session: separate session dirs are independent" {
	local dir1="$BATS_TEST_TMPDIR/sessions/scope-a"
	local dir2="$BATS_TEST_TMPDIR/sessions/scope-b"
	mkdir -p "$dir1" "$dir2"

	local is1="" args1=() is2="" args2=()
	_resolve_chat_session "$dir1" "" is1 args1
	_resolve_chat_session "$dir2" "" is2 args2

	[[ "$is1" == "1" ]]
	[[ "$is2" == "1" ]]
	[[ "${args1[1]}" != "${args2[1]}" ]]
}

# ---------------------------------------------------------------------------
# _validate_chat_passthrough
# ---------------------------------------------------------------------------

@test "_validate_chat_passthrough: accepts valid passthrough flags" {
	local pt=(--model sonnet --verbose)
	run _validate_chat_passthrough pt

	[[ "$status" -eq 0 ]]
}

@test "_validate_chat_passthrough: rejects --session-id" {
	local pt=(--session-id abc123)
	run _validate_chat_passthrough pt

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--session-id is managed by git-ai"* ]]
}

@test "_validate_chat_passthrough: rejects --resume" {
	local pt=(--resume abc123)
	run _validate_chat_passthrough pt

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--resume is managed by git-ai"* ]]
}
