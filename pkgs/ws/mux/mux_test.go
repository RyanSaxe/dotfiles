package mux_test

import (
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
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

// A tmux Snapshot lists each session and pane: the pane going to the session
// lands on, the pane marked agent, and the folder each runs in. tmux reports
// no status, so every session is Open.
func TestATmuxSnapshot(t *testing.T) {
	if _, err := exec.LookPath("tmux"); err != nil {
		t.Skip("tmux is not installed")
	}
	// A server of its own, in a short folder, since a socket's path is
	// limited to about 100 bytes. Its commands name the socket, and the
	// backend finds it through TMUX_TMPDIR.
	dir, err := os.MkdirTemp("/tmp", "mux")
	if err != nil {
		t.Fatal(err)
	}
	socket := filepath.Join(dir, fmt.Sprintf("tmux-%d", os.Getuid()), "default")
	if err := os.Mkdir(filepath.Dir(socket), 0o700); err != nil {
		t.Fatal(err)
	}
	tmux := func(args ...string) string {
		t.Helper()
		out, err := exec.Command("tmux", append([]string{"-S", socket, "-f", "/dev/null"}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatalf("tmux %v: %v %s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	t.Cleanup(func() {
		exec.Command("tmux", "-S", socket, "kill-server").Run()
		os.RemoveAll(dir)
	})
	t.Setenv("TMUX_TMPDIR", dir)
	// A program run outside a terminal, as by launchd, gets no locale.
	for _, v := range []string{"LC_ALL", "LC_CTYPE", "LANG"} {
		t.Setenv(v, "")
	}
	work, err := filepath.EvalSymlinks(t.TempDir()) // tmux reports the real path
	if err != nil {
		t.Fatal(err)
	}
	tmux("new-session", "-d", "-s", "api", "-c", work)
	agent := tmux("split-window", "-d", "-t", "api:", "-c", work, "-P", "-F", "#{pane_id}")
	tmux("set-option", "-p", "-t", agent, "@ws", "agent")
	tmux("new-session", "-d", "-s", "web", "-c", work)

	s, err := mux.Detect(func(string) string { return "" }, "").Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	var labels []string
	for _, session := range s.Sessions {
		labels = append(labels, session.Label)
	}
	if want := []string{"api", "web"}; !slices.Equal(labels, want) {
		t.Errorf("the sessions are %v, want %v", labels, want)
	}
	lands, ok := s.Landing(s.Sessions[0].ID)
	if !ok || lands.ID == agent || lands.Folder != work {
		t.Errorf("going to api lands on %+v, want its first pane, in %s", lands, work)
	}
	if i := slices.IndexFunc(s.Panes, func(p mux.Pane) bool { return p.Agent }); i < 0 || s.Panes[i].ID != agent {
		t.Errorf("the pane marked agent isn't %s in %+v", agent, s.Panes)
	}
	if got := s.Statuses(); !maps.Equal(got, map[string]mux.Status{"api": mux.Open, "web": mux.Open}) {
		t.Errorf("the statuses are %v, want both sessions open", got)
	}
}
