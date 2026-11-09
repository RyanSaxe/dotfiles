package main

import (
	"os/exec"
	"testing"
)

// An agent starts when ws types its command into the pane's zsh, so a prompt
// zsh reads back differently starts the agent on other words, or runs part of
// the prompt as a command.
func TestZshReadsQuotedWordsBackUnchanged(t *testing.T) {
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("zsh is not installed")
	}
	for _, word := range []string{
		"plain-word_1.2", "fix the 'bug' now", `say "hi" & don't stop`, "$(touch pwned) `id` $HOME",
		"=ls", "~/notes", "a;b|c>d", "two\nlines", "",
	} {
		out, err := exec.Command(zsh, "-f", "-c", "printf %s "+quote(word)).Output()
		if err != nil || string(out) != word {
			t.Errorf("zsh read %q back as %q (%v)", word, out, err)
		}
	}
}
