# Ryan's MacBook Pro.
{
  dotfiles = {
    user = "ryansaxe";
    roles = [
      "base"
      "gui"
      "personal"
    ];
    repo = "/Users/ryansaxe/generic/dotfiles";
    git.email = "ryancsaxe+1@gmail.com";
    ws = {
      agent = "claude";
      openAs = "tab";
    };
    vault = {
      dir = "/Users/ryansaxe/generic/vault";
      remote = "git@github.com:RyanSaxe/vault.git";
    };
  };
}
