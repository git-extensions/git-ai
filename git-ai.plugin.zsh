# git-ai.plugin.zsh — zsh plugin entry point
#
# Adds the git-ai binary to PATH so git discovers it as a custom command.
# Compatible with zinit, oh-my-zsh, antigen, zplug, and manual sourcing.

export PATH="${0:A:h}:$PATH"
