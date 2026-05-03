#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Claude provider functions for git-ai

# Print the default Claude model for git-ai commands
#
# Usage: _get_claude_default_model
_get_claude_default_model() {
	printf '%s' "haiku"
}

# Send a prompt to Claude and print the response
#
# Usage: echo "prompt" | _ask_claude MODEL
_ask_claude() {
	local agent_model="$1"

	MAX_THINKING_TOKENS=0 claude -p \
		--model="$agent_model" \
		--disable-slash-commands \
		--setting-sources='' \
		--system-prompt='' \
		--tools='' \
		- || true
}
