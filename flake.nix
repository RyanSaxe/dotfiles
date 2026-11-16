{
  description = "Ryan's computers: nix-darwin for each Mac, home-manager for the user everywhere";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin-palette = {
      url = "github:catppuccin/palette";
      flake = false;
    };
    pair = {
      url = "github:RyanSaxe/pair/develop";
      flake = false;
    };
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      # Each computer is a host file under hosts/ that sets its roles.
      macs = {
        mac = {
          system = "aarch64-darwin";
          user = "ryansaxe";
        };
      };
      # A Linux computer has a home config and no system config.
      linux = {
        linux = {
          system = "x86_64-linux";
          user = "ryansaxe";
        };
      };
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      # The only unfree packages: Claude Code, which Linux installs from
      # nixpkgs, and Copilot CLI.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
              "github-copilot-cli"
            ];
        };
      specialArgs = { inherit inputs; };
    in
    {
      # lib.mac builds a Mac's system config and lib.home a home config,
      # each from a host file. `name` is the computer's name in
      # darwinConfigurations and homeConfigurations, which the switch
      # commands build. A private flake builds its own computers with them,
      # as docs/setup.md shows.
      lib = {
        mac =
          {
            name,
            system,
            host,
          }:
          nix-darwin.lib.darwinSystem {
            inherit specialArgs;
            modules = [
              ./modules/options.nix
              ./modules/darwin
              host
              {
                nixpkgs.hostPlatform = system;
                dotfiles.host = name;
              }
            ];
          };

        home =
          {
            name,
            system,
            host,
          }:
          home-manager.lib.homeManagerConfiguration {
            pkgs = pkgsFor system;
            extraSpecialArgs = specialArgs;
            modules = [
              ./modules/options.nix
              ./modules/home
              host
              { dotfiles.host = name; }
            ];
          };
      };

      darwinConfigurations = builtins.mapAttrs (
        name: host:
        self.lib.mac {
          inherit name;
          inherit (host) system;
          host = ./hosts/${name}.nix;
        }
      ) macs;

      homeConfigurations = nixpkgs.lib.mapAttrs' (
        name: host:
        nixpkgs.lib.nameValuePair "${host.user}@${name}" (
          self.lib.home {
            inherit name;
            inherit (host) system;
            host = ./hosts/${name}.nix;
          }
        )
      ) (macs // linux);

      packages = nixpkgs.lib.genAttrs systems (system: {
        ws = (pkgsFor system).callPackage ./pkgs/ws { };
        pair = (pkgsFor system).callPackage ./pkgs/pair { src = inputs.pair; };
      });

      formatter = nixpkgs.lib.genAttrs systems (system: (pkgsFor system).nixfmt);
    };
}
