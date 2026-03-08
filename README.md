# git-ai

AI-powered git commands — generate commit messages, explain changes, and chat
about diffs right in your terminal, powered by Claude.

```bash
git add -p && git ai commit
git ai explain HEAD~3
git ai chat main
```

## Prerequisites

- [Git](https://git-scm.com/) — `brew install git`
- [Bash](https://www.gnu.org/software/bash/) 4.4+ — `brew install bash` (macOS ships 3.x)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code)
- [Gum](https://github.com/charmbracelet/gum) — `brew install gum`

## Installation

### Nix (recommended)

Run directly without installing:

```bash
nix run github:git-extensions/git-ai -- commit
```

Or install into your profile:

```bash
nix profile install github:git-extensions/git-ai
```

### Manual

Symlink the `git-ai` script onto your `$PATH` so git discovers it as a custom
command:

```bash
ln -s /path/to/git-extensions/git-ai/git-ai /usr/local/bin/git-ai
```

Then use it as `git ai <command>`.

## Usage

### Commit

Generates a conventional commit message from your staged changes. Use
`-d`/`--description` to provide extra context or constraints that guide
the AI when writing the message.

```bash
git add -p
git ai commit
git ai commit -d "focus on the security improvements"
git ai commit -- --signoff
git ai commit -- --no-verify
```

### Explain

Generates a plain-language explanation of git changes and prints it to stdout.
With no arguments it explains your staged changes. Pass a ref to explain what
diverged from that point, or pass two refs for an explicit range.

```bash
git ai explain                        # staged changes (default)
git ai explain HEAD~3                 # changes since HEAD~3
git ai explain HEAD~3..HEAD           # explicit range
git ai explain main                   # changes since main
git ai explain main feature-branch    # diff between two refs
git ai explain -d "focus on auth"     # with extra context
```

### Chat

Opens an interactive AI session with the diff loaded as context. Each
invocation starts a fresh session.

```bash
git ai chat                           # chat about staged changes
git ai chat HEAD~3                    # chat about changes since HEAD~3
git ai chat main                      # chat about branch divergence from main
git ai chat pr-122-branch             # chat about a specific branch
git ai chat HEAD~3..HEAD              # explicit range
git ai chat -d "any security issues?" # with a specific focus
git ai chat -- --model sonnet         # pass flags to the agent
```

## Configuration

Override the AI provider and model via `git config`.

| Key                | Default  | Description                  |
| ------------------ | -------- | ---------------------------- |
| `ai.agent`         | `claude` | AI agent binary              |
| `ai.model`         | `haiku`  | Model for all commands       |
| `ai.commit.model`  |          | Model override for `commit`  |
| `ai.explain.model` |          | Model override for `explain` |

Per-command keys take priority over `ai.model`. For `chat`, pass `-- --model <model>` to override the agent model per session.

```bash
# Set the default model
git config --global ai.model haiku

# Use a stronger model for commits
git config --global ai.commit.model sonnet

# Use a stronger model for a single chat session
git ai chat -- --model sonnet
```

## See Also

- [git-fzf](https://github.com/git-extensions/git-fzf) — Fuzzy finder for git worktrees

## License

[MIT](LICENSE) — Copyright (c) 2025 git-extensions

<!-- markdownlint-disable-file MD013 -->
