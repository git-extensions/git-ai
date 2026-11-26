#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Pi provider functions for git-ai

# Print the default Pi model for git-ai commands
#
# Pi has no single built-in model: it resolves one from the configured
# provider and credentials. Returning nothing leaves --model unset so Pi
# picks its own default.
#
# Usage: _get_pi_default_model
_get_pi_default_model() {
	printf '%s' ""
}

# Send a prompt to Pi in non-interactive (print) mode
#
# Pi prepends the piped prompt to the first message and prints only the final
# assistant text to stdout. Tools, project resources, and sessions are all
# disabled so the run is a deterministic, side-effect free one-shot.
#
# Usage: echo "prompt" | _ask_pi MODEL
_ask_pi() {
	local agent_model="$1"
	local pi_args=(
		--print
		--no-session
		--no-context-files
		--no-mcp
		--no-tools
		--no-extensions
		--no-skills
		--no-prompt-templates
		--no-approve
	)

	if [[ -n "$agent_model" ]]; then
		pi_args+=(--model "$agent_model")
	fi

	local output error_file
	error_file=$(mktemp "${TMPDIR:-/tmp}/git-ai-pi-error.XXXXXX")
	if ! output=$(pi "${pi_args[@]}" 2>"$error_file"); then
		echo "git-ai: pi failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$error_file"
		return 1
	fi
	rm -f "$error_file"

	if [[ -z "$output" ]]; then
		echo "git-ai: pi returned an empty response" >&2
		return 1
	fi
	printf '%s' "$output"
}
