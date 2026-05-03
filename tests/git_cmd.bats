#!/usr/bin/env bats

# Unit tests for provider dispatch in scripts/git_cmd.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _git_ai_source_dir="$REPO_ROOT"
	export TEST_AGENT=""
	export TEST_MODEL=""
	export TEST_CODEX_FAIL=""

	gum() {
		if [[ "$1" == "log" ]]; then
			shift
			shift
			shift
			echo "$@"
		fi
	}

	git() {
		if [[ "$1" == "config" && "$2" == "ai.agent" ]]; then
			if [[ -n "$TEST_AGENT" ]]; then
				printf '%s' "$TEST_AGENT"
			fi
			return 0
		fi
		if [[ "$1" == "config" && "$2" == "ai.model" ]]; then
			if [[ -n "$TEST_MODEL" ]]; then
				printf '%s' "$TEST_MODEL"
			fi
			return 0
		fi
		return 0
	}

	claude() {
		printf '%s' "$*" >"$CLAUDE_ARGS_FILE"
		cat >/dev/null
		printf 'claude message'
	}

	codex() {
		printf '%s' "$*" >"$CODEX_ARGS_FILE"
		local output_file=""
		while [[ $# -gt 0 ]]; do
			if [[ "$1" == "--output-last-message" ]]; then
				output_file="$2"
				break
			fi
			shift
		done
		cat >/dev/null
		if [[ -n "$TEST_CODEX_FAIL" ]]; then
			echo "codex session error" >&2
			return 1
		fi
		printf 'codex message' >"$output_file"
		printf 'codex progress'
	}

	export -f gum git claude codex

	CLAUDE_ARGS_FILE="$BATS_TEST_TMPDIR/claude_args"
	CODEX_ARGS_FILE="$BATS_TEST_TMPDIR/codex_args"
	export CLAUDE_ARGS_FILE CODEX_ARGS_FILE

	# Source git_cmd.sh inside a subshell and import only the function
	# definitions so its shell options do not leak into bats.
	# shellcheck disable=SC2155
	eval "$(
		# shellcheck source=../scripts/git_cmd.sh
		source "$REPO_ROOT/scripts/git_cmd.sh"
		declare -f _get_agent _get_agent_default_model _get_agent_model
		declare -f _get_claude_default_model _get_codex_default_model
		declare -f _ask_claude _ask_codex _cmd_ask
	)"
}

@test "_get_agent defaults to claude" {
	run _get_agent

	[[ "$status" -eq 0 ]]
	[[ "$output" == "claude" ]]
}

@test "_get_agent_model defaults to haiku for claude" {
	run _get_agent_model claude

	[[ "$status" -eq 0 ]]
	[[ "$output" == "haiku" ]]
}

@test "_get_agent_default_model delegates to claude provider" {
	run _get_agent_default_model claude

	[[ "$status" -eq 0 ]]
	[[ "$output" == "haiku" ]]
}

@test "_get_agent_model defaults to gpt-5.4-mini for codex" {
	run _get_agent_model codex

	[[ "$status" -eq 0 ]]
	[[ "$output" == "gpt-5.4-mini" ]]
}

@test "_get_agent_default_model delegates to codex provider" {
	run _get_agent_default_model codex

	[[ "$status" -eq 0 ]]
	[[ "$output" == "gpt-5.4-mini" ]]
}

@test "_get_agent_model uses configured global model" {
	TEST_MODEL="custom-model"

	run _get_agent_model codex

	[[ "$status" -eq 0 ]]
	[[ "$output" == "custom-model" ]]
}

@test "_ask_claude invokes claude with model and prompt on stdin" {
	run _ask_claude sonnet <<<"prompt"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "claude message" ]]
	[[ "$(cat "$CLAUDE_ARGS_FILE")" == *"--model=sonnet"* ]]
}

@test "_cmd_ask dispatches to claude with explicit model" {
	TEST_AGENT="claude"

	run _cmd_ask sonnet <<<"prompt"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "claude message" ]]
	[[ "$(cat "$CLAUDE_ARGS_FILE")" == *"--model=sonnet"* ]]
}

@test "_cmd_ask dispatches to codex and prints only final message" {
	TEST_AGENT="codex"

	run _cmd_ask gpt-5.4-mini <<<"prompt"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "codex message" ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"exec"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--ephemeral"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--ignore-user-config"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--sandbox read-only"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--ask-for-approval never"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--disable web_search_cached"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--disable web_search_request"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--disable image_generation"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--ignore-rules"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"--model gpt-5.4-mini"* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"model_reasoning_summary=\"none\""* ]]
	[[ "$(cat "$CODEX_ARGS_FILE")" == *"model_verbosity=\"low\""* ]]
}

@test "_ask_codex reports provider stderr on failure" {
	TEST_CODEX_FAIL=1

	run _ask_codex gpt-5.4-mini <<<"prompt"

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"git-ai: codex failed to generate a response"* ]]
	[[ "$output" == *"codex session error"* ]]
}

@test "_cmd_ask rejects unsupported agents" {
	TEST_AGENT="unknown"

	run _cmd_ask <<<"prompt"

	[[ "$status" -eq 1 ]]
	[[ "$output" == "Unsupported agent 'unknown' (supported: claude, codex)" ]]
}
