# tmux, with one patch. tmux 3.8 drops a popup's output while a pane under
# it scrolls: it defers the window's redraw, writes nothing to the terminal
# until that redraw, and then redraws the window without the popup. With
# the patch, a popup that printed during the wait is redrawn with the
# window.
#
# The bug is reported as https://github.com/tmux/tmux/issues/5906. tmux's
# master branch has no such bug: commit 34cd5da4e removed popup.c, and
# master passes the check below. So the patch fails to apply to a release
# that fixes the bug the same way or has no popup.c. When that fails a
# build, delete this package and use pkgs.tmux again.
{
  tmux,
  python3,
}:
tmux.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./overlay-redraw.patch ];

  # The check fails on a tmux without the fix, so a build fails if the
  # patch stops working. It also fails if tmux redraws a popup that printed
  # nothing, which tmux 3.8 stopped doing because the popup flickered.
  nativeInstallCheckInputs = old.nativeInstallCheckInputs ++ [ python3 ];
  postInstallCheck = ''
    TMUX_TMPDIR=$TMPDIR python3 ${./check_overlay_redraw.py} $out/bin/tmux
  '';
})
