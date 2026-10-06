{
  pkgs,
  username,
  hostname,
  ...
}:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = hostname;
  networking.computerName = hostname;
  networking.localHostName = hostname;

  system = {
    stateVersion = 6;
    primaryUser = username;
  };

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Determinate Nix manages the daemon; nix-darwin must not.
  # See: https://docs.determinate.systems/
  nix.enable = false;

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    git
  ];
}
