# Codex Support Plan

## Goal

Add Codex as a supported `git-ai` agent alongside Claude, selectable through the
existing `ai.agent` git config key.

## Original State

- `ai.agent` defaults to `claude`.
- `scripts/git_cmd.sh` dispatches prompts only to the `claude` CLI.
- `git-ai` checks for `claude` during startup even when another agent would be
  selected.
- Documentation and package metadata describe Claude as the only provider.

## Proposed User Experience

```bash
git config --global ai.agent codex
git config --global ai.model gpt-5.4-mini
git ai commit
```

Existing Claude users should not need to change anything:

```bash
git config --global ai.agent claude
git config --global ai.model haiku
```

## Implementation Steps

1. Make dependency checks agent-aware.
   - Always require `git` and `gum`.
   - Resolve `ai.agent` before checking the AI CLI.
   - Require `claude` only for `ai.agent=claude`.
   - Require `codex` only for `ai.agent=codex`.
   - Report supported agent names when the configured agent is unknown.

2. Add Codex dispatch in `scripts/git_cmd.sh`.
   - Extend `_cmd_ask` with a `codex` case.
   - Keep stdin prompt handling identical to the Claude path.
   - Pass the configured model when `ai.model` or `ai.commit.model` is set.
   - Ensure command output remains the raw generated commit message.

3. Preserve existing configuration behavior.
   - Keep `ai.agent=claude` as the default.
   - Keep `ai.commit.model` taking precedence over `ai.model`.
   - Avoid changing the commit prompt unless Codex needs provider-neutral
     wording.

4. Update documentation and packaging text.
   - Document Codex installation as an alternative requirement.
   - Update the configuration table to list `claude` and `codex`.
   - Add Codex examples.
   - Make Nix metadata provider-neutral.

5. Add tests.
   - Unit-test agent resolution and unsupported-agent errors.
   - Unit-test that Claude and Codex command lines are selected correctly.
   - Test dependency checks with mocked commands for both agents.
   - Keep existing commit argument tests unchanged.

## Decisions

- Codex uses `codex exec` with stdin prompt input.
- Codex final output is read through `--output-last-message` so progress output
  does not become part of the commit message.
- Provider-specific command implementations live in `scripts/git_cmd_claude.sh`
  and `scripts/git_cmd_codex.sh`.
- `ai.agent=codex` defaults to `gpt-5.4-mini` when neither `ai.commit.model`
  nor `ai.model` is set.
- Claude keeps the existing `haiku` default.

## Validation

- Run `bats tests/git_commit.bats tests/git_cmd.bats tests/git_ai.bats`.
- Add and run tests for `scripts/git_cmd.sh` provider dispatch.
- Add and run tests for agent-aware dependency checks.
- Run `shellcheck git-ai scripts/*.sh`.
- Manually verify `git ai commit` with mocked staged changes for both
  `ai.agent=claude` and `ai.agent=codex`.
