# The agents' status line, which shows the prompt's facts in its colors.
{ t, ... }:
{
  "ai-statusline-colors.js" = "module.exports = ${
    builtins.toJSON {
      faint = t.faint;
      project = t.repo.project;
      branch = t.repo.branch;
      branchBehind = t.repo.behind;
      clean = t.repo.clean;
      dirty = t.repo.dirty;
      model = t.info;
    }
  };\n";
}
