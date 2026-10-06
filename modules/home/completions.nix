# Zsh completions for CLI subcommands (brew, gh, uv, eza, …).
# Completion files must be on $fpath *before* compinit.
{
  lib,
  config,
  ...
}:
let
  # Relative to $HOME; matches XDG data home default.
  userCompletionsRel = ".local/share/zsh/site-functions";
  userCompletions = "${config.home.homeDirectory}/${userCompletionsRel}";
in
{
  # Dedicated dir for any generated completion scripts.
  home.file."${userCompletionsRel}/.keep".text = "";

  # Drop stale dump whenever HM activates so newly linked _* files are picked up.
  home.activation.refreshZshCompdump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -f ${config.home.homeDirectory}/.zcompdump ${config.home.homeDirectory}/.zcompdump-*
  '';

  programs.zsh.initContent = lib.mkOrder 550 ''
    # Subcommand completions: Homebrew + Nix HM profile + optional generated.
    # Keep these ahead of compinit (HM default order ~1000 for initExtra).
    typeset -U fpath
    fpath=(
      ${userCompletions}
      /opt/homebrew/share/zsh/site-functions(N)
      /usr/local/share/zsh/site-functions(N)
      /etc/profiles/per-user/$USER/share/zsh/site-functions(N)
      $HOME/.nix-profile/share/zsh/site-functions(N)
      $fpath
    )
  '';
}
