{
  config,
  pkgs,
  username,
  ...
}:
{
  imports = [ ../../modules/home ];

  home = {
    inherit username;
    homeDirectory = "/Users/${username}";
    stateVersion = "25.11";
  };

  # Set your git identity locally or uncomment:
  # programs.git.userName = "Your Name";
  # programs.git.userEmail = "you@example.com";

  programs.home-manager.enable = true;
}
