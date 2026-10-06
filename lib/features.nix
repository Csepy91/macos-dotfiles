# Feature flag defaults and helpers.
# hosts/<name>/features.nix should return an attrset matching this schema.
{
  defaults = {
    cli = {
      bat = true;
      btop = true;
      duti = true;
      eza = true;
      fd = true;
      fzf = true;
      gh = true;
      git = true;
      ncdu = true;
      ripgrep = true;
      starship = true;
      tldr = true;
      uv = true;
      zoxide = true;
      yazi = true;
    };

    rice = {
      omniwm = true;
      sketchybar = true;
      jankyborders = true;
      skhd = true;
      ghostty = true;
      stylix = true;
    };

    apps = {
      cursor = true;
      sublimeText = true;
      teamviewer = false;
      transmission = true;
      iina = true;
      libreoffice = true;
      geForceNow = false;
    };
  };

  # Merge user features over defaults (shallow per section).
  merge =
    user:
    let
      d = {
        cli = {
          bat = true;
          btop = true;
          duti = true;
          eza = true;
          fd = true;
          fzf = true;
          gh = true;
          git = true;
          ncdu = true;
          ripgrep = true;
          starship = true;
          tldr = true;
          uv = true;
          zoxide = true;
          yazi = true;
        };
        rice = {
          omniwm = true;
          sketchybar = true;
          jankyborders = true;
          skhd = true;
          ghostty = true;
          stylix = true;
        };
        apps = {
          cursor = true;
          sublimeText = true;
          teamviewer = false;
          transmission = true;
          iina = true;
          libreoffice = true;
          geForceNow = false;
        };
      };
    in
    {
      cli = d.cli // (user.cli or { });
      rice = d.rice // (user.rice or { });
      apps = d.apps // (user.apps or { });
    };
}
