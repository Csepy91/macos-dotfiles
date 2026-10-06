{
  lib,
  config,
  pkgs,
  ...
}:
let
  f = config.features.cli;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = true;
    };

    shellAliases = lib.mkMerge [
      {
        ".." = "cd ..";
        "..." = "cd ../..";
        reload = "exec zsh";
      }
      (lib.mkIf (!f.eza) {
        ll = "ls -la";
        la = "ls -la";
      })
      (lib.mkIf f.eza {
        ls = "eza --icons --group-directories-first";
        l = "eza -l --icons --group-directories-first --git";
        ll = "eza -la --icons --group-directories-first --git";
        la = "eza -a --icons --group-directories-first";
        lt = "eza --tree --icons --level=2";
        tree = "eza --tree --icons";
      })
      (lib.mkIf f.zoxide {
        cd = "z";
        cdi = "zi";
      })
      (lib.mkIf f.bat {
        cat = "bat --paging=never";
      })
    ];

    initContent = lib.mkOrder 1000 ''
      # Homebrew env (Apple Silicon / Intel)
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    '';
  };

  programs.starship = lib.mkIf f.starship {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages =
    with pkgs;
    lib.flatten [
      (lib.optional f.eza eza)
      (lib.optional f.fd fd)
      (lib.optional f.ncdu ncdu)
      (lib.optional f.ripgrep ripgrep)
      (lib.optional f.tldr tldr)
      (lib.optional f.uv uv)
      (lib.optional f.duti duti)
      zsh-completions
    ];
}
