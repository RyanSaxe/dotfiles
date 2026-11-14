# Ghostty's two shaders, from config/ghostty/shaders, with the colors they
# paint: the frame in chrome, and the cursor trail in the accent pair.
# Ghostty's own colors come from terminal.nix, which Rex's come from too.
{ lib, t, ... }:
let
  hex = color: "0x${lib.removePrefix "#" color}";
  shader =
    name: defines: lib.concatLines defines + builtins.readFile ../../config/ghostty/shaders/${name};
in
{
  "frame.glsl" = shader "frame.glsl" [ "#define FRAME_HEX ${hex t.chrome}" ];
  "cursor_trail.glsl" = shader "cursor_trail.glsl" [
    "#define TRAIL_HEX ${hex t.accent}"
    "#define TRAIL_ACCENT_HEX ${hex t.second}"
  ];
}
