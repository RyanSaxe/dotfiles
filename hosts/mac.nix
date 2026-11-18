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
    # The built-in display gave AeroSpace a 20-point top gap against 52
    # elsewhere, which keeps windows level under the notch.
    notchInset = 32;
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
