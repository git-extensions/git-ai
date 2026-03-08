# git-ai

Stop writing commit messages by hand. `git-ai` generates precise, conventional
commit messages from your staged changes — powered by Claude, right in your
terminal.

```bash
git add -p && git ai commit
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

### Zsh Plugin

The plugin adds `git-ai` to your `$PATH` so git discovers it as a custom command (`git ai`).

> **Note:** Bash 4.4+ is still required. On macOS: `brew install bash`.

**zinit**

```zsh
zinit light git-extensions/git-ai
```

**oh-my-zsh**

```zsh
# Clone into oh-my-zsh custom plugins directory
git clone https://github.com/git-extensions/git-ai \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/git-ai

# Add to plugins list in ~/.zshrc
plugins=(... git-ai)
```

**antigen**

```zsh
antigen bundle git-extensions/git-ai
```

**zplug**

```zsh
zplug "git-extensions/git-ai"
```

**Manual**

```zsh
# In ~/.zshrc
source /path/to/git-ai/git-ai.plugin.zsh
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

## See Also

- [git-fzf](https://github.com/git-extensions/git-fzf) — Fuzzy finder for git worktrees

## License

[MIT](LICENSE) — Copyright (c) 2025 git-extensions

<!-- markdownlint-disable-file MD013 -->
