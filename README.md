# git-ai

[![CI](https://github.com/git-extensions/git-ai/actions/workflows/test.yml/badge.svg)](https://github.com/git-extensions/git-ai/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/git-extensions/git-ai)](https://github.com/git-extensions/git-ai/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Stop writing commit messages by hand. `git-ai` generates precise, conventional
commit messages from your staged changes — powered by Claude, right in your
terminal.

```bash
git add -p && git ai commit
```

## Requirements

- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)
- [Gum](https://github.com/charmbracelet/gum) (`gum`)

**macOS (Homebrew):**

```bash
brew install bash gum
```

**Nix:**

```bash
nix profile install nixpkgs#bash nixpkgs#gum
```

Install `claude` separately: [Claude Code installation guide](https://docs.anthropic.com/en/docs/claude-code/setup)

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

### Zsh Plugin

The plugin adds `git-ai` to your `$PATH` so git discovers it as a custom command (`git ai`).

> **Note:** Bash 4.4+ is still required. On macOS: `brew install bash`.

```zsh
zinit light git-extensions/git-ai
```

### Manual (symlink)

Symlink the `git-ai` script onto your `$PATH` so git discovers it as a custom
command:

```bash
ln -s /path/to/git-extensions/git-ai/git-ai /usr/local/bin/git-ai
```

Then use it as `git ai <command>`.

## Usage

```bash
git ai commit [-d <DESCRIPTION>] [GIT_COMMIT_OPTIONS]
```

### Commit

Generates a conventional commit message from your staged changes. Use
`-d`/`--description` to provide extra context or constraints that guide
the AI when writing the message.

```bash
git add -p
git ai commit
git ai commit -d "focus on the security improvements"
git ai commit --signoff
git ai commit --no-verify
```

## Configuration

Override the AI provider and model via `git config`.

| Key               | Default     | Description                 |
| ----------------- | ----------- | --------------------------- |
| `ai.agent`        | `claude`    | AI agent (`claude`)         |
| `ai.model`        | `haiku`     | Model for all commands      |
| `ai.commit.model` |             | Model override for `commit` |

Per-command keys take priority over `ai.model`.

```bash
# Set the default model
git config --global ai.model haiku

# Use a stronger model for commits
git config --global ai.commit.model sonnet
```

## The git-extensions Ecosystem

| Repo | What it provides |
|------|-----------------|
| **git-ai** ← you are here | AI-powered commit messages for git |
| [git-fzf](https://github.com/git-extensions/git-fzf) | Fuzzy finder for git |

## License

[MIT](LICENSE) — Copyright (c) 2025 git-extensions

<!-- markdownlint-disable-file MD013 -->
