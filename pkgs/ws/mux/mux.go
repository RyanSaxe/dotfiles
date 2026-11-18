// Package mux drives the terminal multiplexer that holds sessions, Rex or
// tmux. Each session is labeled after its folder, so a program finds it
// again without keeping state of its own. In tmux, an agent is a pane where
// an agent CLI runs, found in the process table on each Snapshot. In Rex,
// it is a pane whose program reports a status.
package mux

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"workspace/kitty"
	"workspace/layout"
)

type Session struct{ ID, Label string }

// A Snapshot is every session and pane, read in one call: one `rex do`
// script in Rex (about 50 ms), one `tmux list-panes -a` in tmux (about 11 ms).
type Snapshot struct {
	Sessions []Session
	Panes    []Pane
}

// A Pane is one terminal in a session: what it runs, in which folder, and
// what its program reports about itself.
type Pane struct {
	Session, Label, ID string
	Landing            bool // where going to the session lands
	Program, Folder    string
	Status             Status // Open when the program reports nothing
	// NeedsYou says the pane's agent needs you and you haven't looked at the
	// pane since.
	NeedsYou   bool
	App, Title string
	Updated    time.Time // the pane's last activity
}

// Landing is the pane going to the session lands on.
func (s Snapshot) Landing(session string) (Pane, bool) {
	i := slices.IndexFunc(s.Panes, func(p Pane) bool { return p.Session == session && p.Landing })
	if i < 0 {
		return Pane{}, false
	}
	return s.Panes[i], true
}

// Statuses is each label's most urgent status.
func (s Snapshot) Statuses() map[string]Status {
	states := map[string]Status{}
	for _, p := range s.Panes {
		if cur, ok := states[p.Label]; !ok || p.Status < cur {
			states[p.Label] = p.Status
		}
	}
	return states
}

// Agents is the panes that report a status.
func (s Snapshot) Agents() []Pane {
	return slices.DeleteFunc(slices.Clone(s.Panes), func(p Pane) bool { return p.Status == Open })
}

// A Backend is the multiplexer holding sessions.
type Backend interface {
	Snapshot() (Snapshot, error)
	// Actions, each on a session or pane that a Snapshot gave.
	Create(label, dir string, panes []layout.Pane) (string, error)
	Show(session string) error
	Focus(p Pane) error                            // shows the pane's session and tab, with the pane focused
	Tab(session, dir string, args ...string) error // a new tab running args, which the session shows and which closes when they exit
	Kill(session string) error
	Capture(p Pane) (string, error) // the pane's text, with its colors
	// Inside says whether the program runs in one of this multiplexer's panes.
	Inside() bool
	Current() (string, error) // the id of the session the program runs in, popups included
	// Images is what the terminal showing the program can do with images.
	Images() kitty.Terminal
	// Follow calls changed at the start and whenever an agent may have
	// changed since, and never returns.
	Follow(changed func())
}

// Detect is Rex inside Rex and tmux otherwise. Outside both, tmux sessions
// still show up in lists, but callers create none, since no terminal would
// show it. client is the Rex app to switch, when the caller knows it.
func Detect(getenv func(string) string, client string) Backend {
	inTmux := getenv("TMUX") != ""
	if getenv("REX_BLOCK") != "" && !inTmux {
		return Rex{Client: client, session: getenv("REX_SESSION"), block: getenv("REX_BLOCK"), term: getenv("TERM_PROGRAM")}
	}
	return Tmux{inside: inTmux, term: getenv("TERM_PROGRAM")}
}

// Find is the id of the session labeled label, or "" when there is none.
func Find(b Backend, label string) (string, error) {
	s, err := b.Snapshot()
	for _, session := range s.Sessions {
		if session.Label == label {
			return session.ID, nil
		}
	}
	return "", err
}

// Label names a folder's session: PROJECT/NAME for a worktree under
// worktreeRoot and the folder's name otherwise. tmux turns dots and colons
// into underscores, so Label does too and a session has one label in either.
func Label(dir, worktreeRoot string) string {
	label := filepath.Base(dir)
	if rel, err := filepath.Rel(worktreeRoot, dir); err == nil && !strings.HasPrefix(rel, "..") && strings.Count(rel, "/") == 1 {
		label = rel
	}
	return strings.NewReplacer(".", "_", ":", "_").Replace(label)
}

// A Status is what an agent reports about itself, most urgent first. Open
// is a session whose programs report nothing.
type Status int

const (
	Blocked Status = iota
	Error
	Done
	Working
	Idle
	Open
)

var statusNames = []string{"blocked", "error", "done", "working", "idle", "open"}

func (s Status) String() string { return statusNames[s] }

// ParseStatus reads a status as Rex reports it. Anything else is Open.
func ParseStatus(s string) (Status, bool) {
	if i := slices.Index(statusNames, s); i >= 0 {
		return Status(i), true
	}
	return Open, false
}

func run(name string, args ...string) (string, error) { return output(exec.Command(name, args...)) }

// output runs cmd and returns its trimmed output. A failure reads as what
// the program printed to stderr.
func output(cmd *exec.Cmd) (string, error) {
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if msg := strings.TrimSpace(stderr.String()); err != nil && msg != "" {
		err = fmt.Errorf("%s: %s", cmd.Args[0], msg)
	}
	return strings.TrimSpace(string(out)), err
}
