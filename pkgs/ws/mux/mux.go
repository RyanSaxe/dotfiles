// Package mux drives the terminal multiplexer that holds sessions, Rex or
// tmux. Each session is labeled after its folder, and the pane running an
// agent is marked "agent" (a Rex block label, a tmux pane option), so a
// program finds both again without keeping state of its own.
package mux

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"workspace/kitty"
	"workspace/layout"
)

type Session struct{ ID, Label string }

// A Backend is the multiplexer holding sessions.
// Pane is what a session's pane is doing, its agent's status or else the
// program it runs, and the folder it runs in.
type Pane struct{ Doing, Folder string }

type Backend interface {
	Sessions() ([]Session, error)
	Create(label, dir string, panes []layout.Pane) (id string, err error)
	Show(id string) error
	Tab(id, dir string, args ...string) error // a new tab running args, which closes when they exit
	Send(id, text string) error               // types text and Enter into the session's agent pane
	Kill(id string) error
	Capture(id string) (string, error) // the text of the pane the session shows
	Landing(id string) Pane            // the pane going to the session lands on
	// Statuses is each session's most urgent agent status, by label.
	Statuses() map[string]Status
	// Inside says whether the program runs in one of this multiplexer's panes.
	Inside() bool
	// Images is what the terminal showing the program can do with images.
	Images() kitty.Terminal
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
	ss, err := b.Sessions()
	for _, s := range ss {
		if s.Label == label {
			return s.ID, nil
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

// run runs a program and returns its trimmed output. A failure reads as what
// the program printed to stderr.
func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if msg := strings.TrimSpace(stderr.String()); err != nil && msg != "" {
		err = fmt.Errorf("%s: %s", name, msg)
	}
	return strings.TrimSpace(string(out)), err
}
