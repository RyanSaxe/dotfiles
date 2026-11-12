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
      # Claude Code is the one unfree package. Linux installs it from nixpkgs.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-code";
        };
      specialArgs = { inherit inputs; };
    in
    {
      darwinConfigurations = builtins.mapAttrs (
        name: host:
        nix-darwin.lib.darwinSystem {
          inherit specialArgs;
          modules = [
            ./modules/options.nix
            ./modules/darwin
            ./hosts/${name}.nix
            {
              nixpkgs.hostPlatform = host.system;
              dotfiles.host = name;
            }
          ];
        }
      ) macs;

      homeConfigurations = nixpkgs.lib.mapAttrs' (
        name: host:
        nixpkgs.lib.nameValuePair "${host.user}@${name}" (
          home-manager.lib.homeManagerConfiguration {
            pkgs = pkgsFor host.system;
            extraSpecialArgs = specialArgs;
            modules = [
              ./modules/options.nix
              ./modules/home
              ./hosts/${name}.nix
              { dotfiles.host = name; }
            ];
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
