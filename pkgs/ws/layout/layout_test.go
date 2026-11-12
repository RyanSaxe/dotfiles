package layout_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"workspace/layout"
)

var builtins = map[string]string{"agent": "[[pane]]\nrun = \"{agent} {prompt}\"\nfocus = true\n\n[[pane]]\nsize = 35\n"}

func TestLoadFillsPlaceholders(t *testing.T) {
	panes, err := layout.Load(t.TempDir(), "agent", builtins, map[string]string{"{agent}": "claude", "{prompt}": "fix the 'bug'"})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := panes[0].Run, `claude 'fix the '\''bug'\'''`; got != want || !panes[0].Agent || !panes[0].Focus {
		t.Errorf("first pane runs %s (agent %v, focus %v), want %s as the focused agent", got, panes[0].Agent, panes[0].Focus, want)
	}
	if p := panes[1]; p.Split != "right" || p.Size != 35 || p.Run != "" {
		t.Errorf("second pane is %+v, want an empty pane split right at 35", p)
	}
}

func TestAFileReplacesABuiltin(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "agent.toml"), []byte("[[pane]]\nrun = \"codex\"\n"), 0o644)
	panes, err := layout.Load(dir, "agent", builtins, nil)
	if err != nil || len(panes) != 1 || panes[0].Run != "codex" {
		t.Errorf("got %+v, %v, want the file's one codex pane", panes, err)
	}
	os.WriteFile(filepath.Join(dir, "bad.toml"), []byte("[[pane]]\nrun = \"x\"\nwidth = 3\n"), 0o644)
	if _, err := layout.Load(dir, "bad", builtins, nil); err == nil {
		t.Error("a layout with an unknown key loaded")
	}
}

// An agent starts when its command is typed into the pane's zsh, so a
// prompt zsh reads back differently starts the agent on other words, or runs
// part of the prompt as a command.
func TestZshReadsQuotedWordsBackUnchanged(t *testing.T) {
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("zsh is not installed")
	}
	for _, word := range []string{
		"plain-word_1.2", "fix the 'bug' now", `say "hi" & don't stop`, "$(touch pwned) `id` $HOME",
		"=ls", "~/notes", "a;b|c>d", "two\nlines", "",
	} {
		out, err := exec.Command(zsh, "-f", "-c", "printf %s "+layout.Quote(word)).Output()
		if err != nil || string(out) != word {
			t.Errorf("zsh read %q back as %q (%v)", word, out, err)
		}
	}
}
