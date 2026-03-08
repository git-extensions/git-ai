#!/usr/bin/env bats

# Unit tests for utility functions in git_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/git_cmd.bats

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
		printf '_git_cmd_dir=%q\n' "$_git_cmd_dir"
		declare -f _split_on_separator _cmd_render
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

@test "_split_on_separator: passes second -- through as passthrough arg" {
	local before=() after=()
	_split_on_separator before after -d "desc" -- --signoff -- --extra

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 3 ]]
	[[ "${after[1]}" == "--" ]]
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
