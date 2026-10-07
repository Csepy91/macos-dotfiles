# macOS rice — zsh (managed via GNU Stow)

# Homebrew env (Apple Silicon / Intel)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Cinematic Noir — master palette + CLI colors (before plugins that read styles)
if [[ -f "${HOME}/.config/theme/colors.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/colors.sh"
fi
if [[ -f "${HOME}/.config/theme/cli.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/theme/cli.sh"
fi

# History
HISTSIZE=50000
SAVEHIST=50000
HISTFILE="${HOME}/.zsh_history"
setopt HIST_IGNORE_DUPS SHARE_HISTORY

# Completions: Homebrew + user site-functions before compinit
typeset -U fpath
fpath=(
  "${HOME}/.local/share/zsh/site-functions"
  /opt/homebrew/share/zsh/site-functions(N)
  /usr/local/share/zsh/site-functions(N)
  $fpath
)

autoload -Uz compinit
compinit

# Plugins (Homebrew)
ZSH_AUTOSUGGESTIONS=""
ZSH_SYNTAX_HIGHLIGHTING=""
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
  ZSH_AUTOSUGGESTIONS="${HOMEBREW_PREFIX}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_SYNTAX_HIGHLIGHTING="${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
[[ -f "$ZSH_AUTOSUGGESTIONS" ]] && source "$ZSH_AUTOSUGGESTIONS"
[[ -f "$ZSH_SYNTAX_HIGHLIGHTING" ]] && source "$ZSH_SYNTAX_HIGHLIGHTING"

# Aliases
alias ..='cd ..'
alias ...='cd ../..'
alias reload='exec zsh'

if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias l='eza -l --icons --group-directories-first --git'
  alias ll='eza -la --icons --group-directories-first --git'
  alias la='eza -a --icons --group-directories-first'
  alias lt='eza --tree --icons --level=2'
  alias tree='eza --tree --icons'
else
  alias ll='ls -la'
  alias la='ls -la'
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
  alias cd='z'
  alias cdi='zi'
fi

if (( $+commands[bat] )); then
  alias cat='bat --paging=never'
fi

if (( $+commands[fzf] )); then
  source <(fzf --zsh) 2>/dev/null || true
fi

if (( $+commands[yazi] )); then
  function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    # Avoid cat — it is aliased to bat, which mangles the path.
    if cwd="$(<$tmp)" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
fi

if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi
