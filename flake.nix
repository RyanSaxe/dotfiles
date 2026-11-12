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
    pair = {
      url = "github:RyanSaxe/pair/develop";
      flake = false;
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
      systems = [
        "aarch64-darwin"
      ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
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
      ) macs;

      packages = nixpkgs.lib.genAttrs systems (system: {
        pair = (pkgsFor system).callPackage ./pkgs/pair { src = inputs.pair; };
      });

      formatter = nixpkgs.lib.genAttrs systems (system: (pkgsFor system).nixfmt);
    };
}
