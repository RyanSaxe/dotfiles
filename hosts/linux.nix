# A Linux box with no screen, which runs Rex's server.
{
  dotfiles = {
    user = "ryansaxe";
    roles = [
      "base"
      "personal"
      "rex-server"
    ];
    repo = "/home/ryansaxe/generic/dotfiles";
    git.email = "ryancsaxe+1@gmail.com";
    ws = {
      agent = "claude";
      openAs = "tab";
    };
    vault = {
      dir = "/home/ryansaxe/generic/vault";
      remote = "git@github.com:RyanSaxe/vault.git";
    };
  };
}
