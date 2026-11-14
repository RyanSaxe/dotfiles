# sketchybar's colors, as the variables its scripts read, in its 0xAARRGGBB
# form. `theme` reloads it.
{ lib, t, ... }:
let
  argb = alpha: color: "0x${alpha}${lib.removePrefix "#" color}";
  colors = {
    BAR_COLOR = argb "ff" t.chrome; # one surface with the window frames
    BORDER_COLOR = argb "ff" t.stroke;
    BAR_SHADOW = "0x33000000"; # black at 20%, a faint line in either mode
    ITEM_BG = "0x00000000";
    ICON_COLOR = argb "ff" t.faint; # present but quiet
    LABEL_COLOR = argb "ff" t.faint;
    ACCENT_COLOR = argb "ff" t.accent;
    NOTIFY_COLOR = argb "ff" t.second;
    WORKSPACE_ACTIVE_FG = argb "ff" t.accent;
    WORKSPACE_ACTIVE_BG = argb "33" t.accent;
    WORKSPACE_INACTIVE_FG = argb "ff" t.faint;
    WORKSPACE_INACTIVE_BG = "0x00000000";
    TIME_NORMAL = argb "ff" t.accent;
    TIME_HIGHLIGHT = argb "ff" t.error; # a meeting is about to start or end
    AGENT_WAITING_FG = argb "ff" t.waiting;
    AGENT_WAITING_BG = argb "33" t.waiting;
    REVIEW_CI_FG = argb "ff" t.error; # a check failed on your pull request
    REVIEW_CI_BG = argb "33" t.error;
    REVIEW_PENDING_FG = argb "ff" t.waiting;
    REVIEW_PENDING_BG = argb "33" t.waiting;
    TASK_OVERDUE_FG = argb "ff" t.error;
    TASK_OVERDUE_BG = argb "33" t.error;
    TASK_TODAY_FG = argb "ff" t.waiting;
    TASK_TODAY_BG = argb "33" t.waiting;
    TASK_TOMORROW_FG = argb "ff" t.info;
    TASK_TOMORROW_BG = argb "33" t.info;
    WARN_COLOR = argb "ff" t.warn;
    DANGER_COLOR = argb "ff" t.error;
  };
in
{
  "sketchybar-colors.sh" = lib.concatLines (
    lib.mapAttrsToList (name: value: ''export ${name}="${value}"'') colors
  );
}
