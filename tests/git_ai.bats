#!/usr/bin/env bats

# Unit tests for the git-ai entrypoint helpers

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	TEST_AGENT=""
	COMMANDS_DIR="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$COMMANDS_DIR"
	PATH="$COMMANDS_DIR:/usr/bin:/bin"
	export TEST_AGENT COMMANDS_DIR PATH

	git() {
		if [[ "$1" == "config" && "$2" == "ai.agent" ]]; then
			if [[ -n "$TEST_AGENT" ]]; then
				printf '%s' "$TEST_AGENT"
			fi
			return 0
		fi
		return 0
	}
	export -f git

	touch "$COMMANDS_DIR/gum" "$COMMANDS_DIR/claude" "$COMMANDS_DIR/codex" "$COMMANDS_DIR/gemini" "$COMMANDS_DIR/jq"
	chmod +x "$COMMANDS_DIR/gum" "$COMMANDS_DIR/claude" "$COMMANDS_DIR/codex" "$COMMANDS_DIR/gemini" "$COMMANDS_DIR/jq"

	# shellcheck source=../git-ai
	source "$REPO_ROOT/git-ai"
}

@test "_check_dependencies defaults to requiring claude" {
	rm "$COMMANDS_DIR/codex"

	run _check_dependencies

	[[ "$status" -eq 0 ]]
}

@test "_check_dependencies requires codex for codex agent" {
	TEST_AGENT="codex"
	rm "$COMMANDS_DIR/claude"

	run _check_dependencies

	[[ "$status" -eq 0 ]]
}

@test "_check_dependencies requires gemini for gemini agent" {
	TEST_AGENT="gemini"
	rm "$COMMANDS_DIR/claude" "$COMMANDS_DIR/codex"

	run _check_dependencies

	[[ "$status" -eq 0 ]]
}

@test "_check_dependencies requires jq for gemini agent" {
	TEST_AGENT="gemini"
	rm "$COMMANDS_DIR/jq"
	# Mock command to fail for jq
	command() {
		if [[ "$2" == "jq" ]]; then
			return 1
		fi
		builtin command "$@"
	}
	export -f command

	run _check_dependencies

	unset -f command
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"missing required dependencies"* ]]
	[[ "$output" == *"jq"* ]]
}

@test "_check_dependencies reports missing configured codex" {
	TEST_AGENT="codex"
	rm "$COMMANDS_DIR/codex"

	run _check_dependencies

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"missing required dependencies"* ]]
	[[ "$output" == *"codex"* ]]
}

@test "_check_dependencies reports missing configured gemini" {
	TEST_AGENT="gemini"
	rm "$COMMANDS_DIR/gemini"

	run _check_dependencies

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"missing required dependencies"* ]]
	[[ "$output" == *"gemini"* ]]
}

@test "_check_dependencies rejects unsupported agents" {
	TEST_AGENT="unknown"

	run _check_dependencies

	[[ "$status" -eq 1 ]]
	[[ "$output" == "git-ai: unsupported agent 'unknown' (supported: claude, codex, gemini)" ]]
}

@test "sourcing git_cmd does not replace git-ai main" {
	# shellcheck source=../scripts/git_cmd.sh
	source "$REPO_ROOT/scripts/git_cmd.sh"

	run main --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"git ai - AI-powered git commands"* ]]
}
