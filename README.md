# git-ai

AI-powered git commands. Generate commit messages from staged changes — all
from your terminal.

![License](https://img.shields.io/github/license/git-extensions/git-ai)
![Version](https://img.shields.io/github/v/release/git-extensions/git-ai)

## Prerequisites

- [Gum](https://github.com/charmbracelet/gum) — macOS: `brew install gum`
- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`) — macOS: `brew install bash`
- [Git](https://git-scm.com/) (`git`)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)

## Installation

Symlink the `git-ai` script onto your `$PATH` so git discovers it as a custom
command:

```bash
ln -s /path/to/git-extensions/git-ai/git-ai /usr/local/bin/git-ai
```

Then use it as `git ai <command>`.

## Usage

```bash
git ai commit [-d <DESCRIPTION>] [-- GIT_COMMIT_OPTIONS]
```

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

## Configuration

Override the AI provider and model via `git config`.

| Key               | Default     | Description                 |
| ----------------- | ----------- | --------------------------- |
| `ai.provider`     | `anthropic` | AI provider (`anthropic`)   |
| `ai.model`        | `haiku`     | Model for all commands      |
| `ai.commit.model` |             | Model override for `commit` |

Per-command keys take priority over `ai.model`.

```bash
# Set the default model
git config --global ai.model haiku

# Use a stronger model for commits
git config --global ai.commit.model sonnet
```

## License

[MIT](LICENSE) — Copyright (c) 2025 git-extensions

<!-- markdownlint-disable-file MD013 -->
