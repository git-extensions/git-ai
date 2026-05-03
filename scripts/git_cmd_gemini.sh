#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Gemini provider functions for git-ai

# Print the default Gemini model for git-ai commands
#
# Usage: _get_gemini_default_model
_get_gemini_default_model() {
	printf '%s' "gemini-2.5-flash"
}

# Send a prompt to Gemini and print the response
#
# Usage: echo "prompt" | _ask_gemini MODEL
_ask_gemini() {
	local agent_model="$1"
	local prompt output error_file
	prompt=$(cat)
	error_file=$(mktemp "${TMPDIR:-/tmp}/git-ai-gemini-error.XXXXXX")

	if ! output=$(
		CI=true gemini \
			--prompt "$prompt" \
			--approval-mode plan \
			--extensions '' \
			--output-format json \
			--skip-trust \
			--model "$agent_model" \
			</dev/null \
			2>"$error_file" | jq -r '.response // empty'
	); then
		echo "git-ai: gemini failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$error_file"
		return 1
	fi
	rm -f "$error_file"

	if [[ -z "$output" ]]; then
		echo "git-ai: gemini returned an empty response" >&2
		return 1
	fi
	printf '%s' "$output"
}
