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
	"time"
	"workspace/mux"
)

// Sessions are found again by their label, so a folder must get the same one
// every time, in a form tmux keeps as it is.
func TestLabel(t *testing.T) {
	for dir, want := range map[string]string{
		"/home/r/worktrees/pair/fix-login":          "pair/fix-login",
		"/home/r/Projects/the-nightly.build":        "Projects/the-nightly_build",
		"/home/r/Projects/Games/magic-the-battling": "Games/magic-the-battling",
		"/home/r/worktrees/pair":                    "worktrees/pair",
		"/home/r/brain":                             "brain",
		"/home/r":                                   "r",
		"/tmp":                                      "tmp",
		"/tmp/scratch":                              "tmp/scratch",
		"/home/r/a.b/c:d/":                          "a_b/c_d",
	} {
		if got := mux.Label(dir, "/home/r"); got != want {
			t.Errorf("%s: got %s, want %s", dir, got, want)
		}
	}
}

type tmuxServer struct {
	dir, socket, work string
}

func startTmuxServer(t *testing.T) tmuxServer {
	t.Helper()
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
	t.Cleanup(func() {
		_ = exec.Command("tmux", "-S", socket, "kill-server").Run() //nolint:gosec // stops throwaway test tmux server
		_ = os.RemoveAll(dir)
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
	return tmuxServer{dir: dir, socket: socket, work: work}
}

func (srv tmuxServer) run(t *testing.T, args ...string) string {
	t.Helper()
	out, err := exec.Command("tmux", append([]string{"-S", srv.socket, "-f", "/dev/null"}, args...)...).CombinedOutput() //nolint:gosec // invokes throwaway test tmux server
	if err != nil {
		t.Fatalf("tmux %v: %v %s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func (srv tmuxServer) linkAgent(t *testing.T, program, name string) string {
	t.Helper()
	path := filepath.Join(srv.dir, name)
	if err := os.Symlink(program, path); err != nil {
		t.Fatal(err)
	}
	return path
}

func waitForTmuxSnapshot(t *testing.T, agyPane string) mux.Snapshot {
	t.Helper()
	backend := mux.Detect(func(string) string { return "" }, "")
	var s mux.Snapshot
	for deadline := time.Now().Add(2 * time.Second); ; time.Sleep(50 * time.Millisecond) {
		var err error
		if s, err = backend.Snapshot(); err != nil {
			t.Fatal(err)
		}
		rang := slices.ContainsFunc(s.Panes, func(p mux.Pane) bool { return p.NeedsYou })
		agyUp := slices.ContainsFunc(s.Panes, func(p mux.Pane) bool { return p.ID == agyPane && p.Status != mux.Open })
		if (rang && agyUp) || time.Now().After(deadline) {
			return s
		}
	}
}

func checkTmuxLabels(t *testing.T, s mux.Snapshot) {
	t.Helper()
	var labels []string
	for _, session := range s.Sessions {
		labels = append(labels, session.Label)
	}
	if want := []string{"api", "web"}; !slices.Equal(labels, want) {
		t.Errorf("the sessions are %v, want %v", labels, want)
	}
	var places []string
	for _, p := range s.Places() {
		places = append(places, p.Label)
	}
	if want := []string{"api", "api/feature", "api/agy", "web"}; !slices.Equal(places, want) {
		t.Errorf("the places are %v, want %v", places, want)
	}
}

func checkTmuxPlaces(t *testing.T, s mux.Snapshot, work, agent string) {
	t.Helper()
	checkTmuxLabels(t, s)
	api, _ := s.Find("api")
	if lands, ok := s.Landing(api); !ok || lands.ID == agent || lands.Folder != work || api.Whole {
		t.Errorf("going to api lands on %+v, want its first pane, in %s, and api is %+v, want the session less a tab", lands, work, api)
	}
	if web, _ := s.Find("web"); !web.Whole || len(web.Tabs) != 2 {
		t.Errorf("web is %+v, want the whole session, its logs tab included", web)
	}
	checkTmuxFeaturePlace(t, s, agent)
}

func checkTmuxFeaturePlace(t *testing.T, s mux.Snapshot, agent string) {
	t.Helper()
	feature, _ := s.Find("api/feature")
	if lands, ok := s.Landing(feature); !ok || lands.ID != agent || !feature.Named || len(feature.Tabs) != 1 {
		t.Errorf("api/feature is %+v and lands on %+v, want its one named tab, landing on the agent", feature, lands)
	}
}

func mustFindPane(t *testing.T, panes []mux.Pane, id string) mux.Pane {
	t.Helper()
	i := slices.IndexFunc(panes, func(p mux.Pane) bool { return p.ID == id })
	if i < 0 {
		t.Fatalf("pane %s is missing from %+v", id, panes)
	}
	return panes[i]
}

func checkTmuxAgents(t *testing.T, s mux.Snapshot, agent, agyPane string) {
	t.Helper()
	if p := mustFindPane(t, s.Panes, agent); !p.NeedsYou || p.Status != mux.Working {
		t.Errorf("the agent that just rang reads %v, needing you %v, want working and needing you", p.Status, p.NeedsYou)
	}
	if p := mustFindPane(t, s.Panes, agyPane); p.Status == mux.Open {
		t.Errorf("the agy pane %s wasn't counted as an agent in %+v", agyPane, s.Panes)
	}
	if slices.ContainsFunc(s.Panes, func(p mux.Pane) bool { return p.ID != agent && p.ID != agyPane && (p.NeedsYou || p.Status != mux.Open) }) {
		t.Errorf("a pane with no agent reports something in %+v", s.Panes)
	}
	if got := s.Statuses(); !maps.Equal(got, map[string]mux.Status{"api": mux.Open, "api/agy": mux.Working, "api/feature": mux.Working, "web": mux.Open}) {
		t.Errorf("the statuses are %v, want api/agy and api/feature working, and api and web open", got)
	}
}

// A tmux Snapshot lists each session and pane: the pane going to the session
// lands on, the pane an agent runs in, and the folder each runs in. A window
// named after a worktree is a place of its own, and the rest of its session
// another.
// The agent needs you once its window's bell rings where no client shows
// it, and works while its window prints. Every other pane is Open.
func TestATmuxSnapshot(t *testing.T) {
	srv := startTmuxServer(t)
	srv.run(t, "new-session", "-d", "-s", "api", "-c", srv.work)
	// The agents are tmux run through links named claude and agy, since ws
	// knows an agent by the name it runs as, waiting on a channel nothing
	// signals. opencode is no longer counted as an agent. macOS kills a copy
	// of a system program, and nixpkgs' sleep is a link to coreutils, which
	// picks its command by that name.
	program, err := exec.LookPath("tmux")
	if err != nil {
		t.Fatal(err)
	}
	claude, agy, opencode := srv.linkAgent(t, program, "claude"), srv.linkAgent(t, program, "agy"), srv.linkAgent(t, program, "opencode")
	// The agent runs in a tab named after a worktree, beside a tab nobody
	// named.
	agent := srv.run(t, "new-window", "-d", "-t", "api:", "-n", "api/feature", "-c", srv.work, "-P", "-F", "#{pane_id}",
		`printf '\a'; exec `+claude+` -S `+srv.socket+` wait-for never`)
	srv.run(t, "split-window", "-d", "-t", agent, "-c", srv.work)
	agyPane := srv.run(t, "new-window", "-d", "-t", "api:", "-n", "api/agy", "-c", srv.work, "-P", "-F", "#{pane_id}",
		`exec `+agy+` -S `+srv.socket+` wait-for never`)
	srv.run(t, "new-session", "-d", "-s", "web", "-c", srv.work)
	// A tab named after no worktree stays part of its session, and opencode
	// does not count as an agent.
	srv.run(t, "new-window", "-d", "-t", "web:", "-n", "logs", "-c", srv.work,
		`exec `+opencode+` -S `+srv.socket+` wait-for never`)

	// tmux reads the bell from the pane's output a moment after it rings, and
	// the agy pane's shell needs a moment to exec agy.
	s := waitForTmuxSnapshot(t, agyPane)
	checkTmuxPlaces(t, s, srv.work, agent)
	checkTmuxAgents(t, s, agent, agyPane)
}

// A Rex agent needs you while it's blocked, and while it's failed or done
// until an app shows its pane, which asks the server for the pane's size.
// The pane you're looking at needs nothing, and nor does a failed or done
// report that came while you looked, which the caller lists in Seen.
func TestARexSnapshotTellsWhichAgentsNeedYou(t *testing.T) {
	bin := t.TempDir()
	script := `#!/bin/sh
cat >/dev/null
cat <<'EOF'
{"sessions": [{"id": "s:api", "label": "api"}, {"id": "s:web", "label": "web"}],
 "panes": [
  {"session": "s:api", "label": "api", "id": "looked-at", "landing": true, "status": "blocked", "updated": "2026-11-17T12:05:00-05:00", "shown": {}},
  {"session": "s:web", "label": "web", "id": "blocked", "landing": true, "status": "blocked", "updated": "2026-11-17T12:05:00-05:00", "shown": {}},
  {"session": "s:web", "label": "web", "id": "failed-unseen", "status": "error", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:00:00Z"]},
  {"session": "s:web", "label": "web", "id": "failed-shown-since", "status": "error", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:06:00Z"]},
  {"session": "s:web", "label": "web", "id": "failed-listed", "status": "error", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:00:00Z"]},
  {"session": "s:web", "label": "web", "id": "unseen", "status": "done", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:00:00Z"]},
  {"session": "s:web", "label": "web", "id": "never-shown", "status": "done", "updated": "2026-11-17T12:05:00-05:00", "shown": {}},
  {"session": "s:web", "label": "web", "id": "shown-since", "status": "done", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:06:00Z"]},
  {"session": "s:web", "label": "web", "id": "listed", "status": "done", "updated": "2026-11-17T12:05:00-05:00", "shown": ["2026-11-17T17:00:00Z"]},
  {"session": "s:web", "label": "web", "id": "working", "status": "working", "updated": "2026-11-17T12:05:00-05:00", "shown": {}}
 ]}
EOF`
	if err := os.WriteFile(filepath.Join(bin, "rex"), []byte(script), 0o700); err != nil { //nolint:gosec // test writes executable fake rex shim to temp PATH
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))

	finished := time.Date(2026, 11, 17, 17, 5, 0, 0, time.UTC)
	s, err := mux.Rex{Shown: "api", Seen: map[string]time.Time{"listed": finished, "failed-listed": finished}}.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	var needing []string
	for _, p := range s.Panes {
		if p.NeedsYou {
			needing = append(needing, p.ID)
		}
	}
	if want := []string{"blocked", "failed-unseen", "unseen", "never-shown"}; !slices.Equal(needing, want) {
		t.Errorf("%v need you, want %v", needing, want)
	}
}
