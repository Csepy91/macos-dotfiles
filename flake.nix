{
  description = "Shareable macOS rice — nix-darwin + Home Manager + Stylix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      stylix,
      ...
    }:
    let
      system = "aarch64-darwin";

      mkDarwin =
        {
          hostname,
          username ? "csepy",
          hostPath ? ./hosts/${hostname},
        }:
        let
          features = import (hostPath + /features.nix);
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              username
              hostname
              features
              ;
          };
          modules = [
            ./modules/features.nix
            {
              # Apply host feature flags into the options tree.
              inherit features;
            }
            stylix.darwinModules.stylix
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit
                    self
                    username
                    hostname
                    features
                    ;
                };
                sharedModules = [
                  ./modules/features.nix
                  { inherit features; }
                ];
                users.${username} = import (hostPath + /home.nix);
              };
            }
            ./modules/darwin
            (hostPath + /configuration.nix)
          ];
        };
    in
    {
      darwinConfigurations = {
        # Template / default host name used by install.sh when cloning hosts/default.
        default = mkDarwin {
          hostname = "default";
          username = "csepy";
          hostPath = ./hosts/default;
        };

        # Current UTM VM hostname (dots replaced for flake attr safety).
        "csepys-Virtual-Machine" = mkDarwin {
          hostname = "csepys-Virtual-Machine";
          username = "csepy";
          hostPath = ./hosts/csepys-Virtual-Machine;
        };
        # CURRENT_HOSTS_END
      };

      # Helper for scripts / docs.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
