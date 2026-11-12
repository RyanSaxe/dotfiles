package mux_test

import (
	"testing"

	"workspace/mux"
)

// Sessions are found again by their label, so a folder must get the same one
// every time, in a form tmux keeps as it is.
func TestLabel(t *testing.T) {
	for dir, want := range map[string]string{
		"/home/r/worktrees/pair/fix-login":   "pair/fix-login",
		"/home/r/Projects/the-nightly.build": "the-nightly_build",
		"/home/r/worktrees/pair":             "pair",
	} {
		if got := mux.Label(dir, "/home/r/worktrees"); got != want {
			t.Errorf("%s: got %s, want %s", dir, got, want)
		}
	}
}
