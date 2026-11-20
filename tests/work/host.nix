# A work Linux box with a placeholder account, built the way a private
# flake builds one, so CI keeps the base and work roles building without
# personal.
{
  dotfiles = {
    user = "placeholder";
    roles = [
      "base"
      "work"
    ];
    repo = "/home/placeholder/generic/dotfiles";
    flake = "/home/placeholder/generic/work-dotfiles";
    git.email = "placeholder@example.com";
    secretsFile = ./secrets.yaml;
  };
}
