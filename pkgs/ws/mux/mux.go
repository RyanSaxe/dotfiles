// Package mux drives the terminal multiplexer that holds sessions, Rex or
// tmux. A folder's terminals are in its place, a session or a tab labeled
// after the folder, so a program finds them again without keeping state of
// its own. In tmux, an agent is a pane where an agent CLI runs, found in the
// process table on each Snapshot. In Rex, it is a pane whose program reports
// a status.
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

// A Pane is one terminal in a session: its tab, what it runs, in which
// folder, and what its program reports about itself. Label is its session's
// label, and TabName is its tab's name when someone named the tab, else "".
// A detached pane has no Tab.
type Pane struct {
	Session, Label, ID string
	Tab, TabName       string
	Focused            bool // where going to its tab lands
	Landing            bool // where going to its session lands: the focused pane of the active tab
	Program, Folder    string
	Status             Status // Open when the program reports nothing
	// NeedsYou says the pane's agent needs you and you haven't looked at the
	// pane since.
	NeedsYou   bool
	App, Title string
	Updated    time.Time // the pane's last activity
}

// place is the label of the place a pane is in: its tab's name when the
// tab is named after a worktree, PROJECT/NAME as Label gives it, and its
// session's label otherwise, so a tab named such as "tests" stays part of
// its session.
func (p Pane) place() string {
	if strings.Count(p.TabName, "/") == 1 {
		return p.TabName
	}
	return p.Label
}

// A Place is where a folder's terminals are, labeled after the folder: the
// tabs named after a worktree in a session, or the session's other tabs,
// under the session's label. Tab is the tab going to the place
// selects, the session's active tab when it is one of the place's and else
// its first. Named says its tabs are named after it, and Whole that it is
// every tab of its session, so closing it closes the session.
type Place struct {
	Label, Session, Tab string
	Tabs                []string
	Named, Whole        bool
}

// Places lists every place, in the order of the sessions and their panes. A
// session with no panes is a place with no tabs.
func (s Snapshot) Places() []Place {
	var places []Place
	for _, p := range s.Panes {
		places = addPaneToPlaces(places, p)
	}
	for i, pl := range places {
		places[i].Whole = !slices.ContainsFunc(places, func(other Place) bool { return other.Session == pl.Session && other.Label != pl.Label })
	}
	for _, session := range s.Sessions {
		if !slices.ContainsFunc(places, func(pl Place) bool { return pl.Session == session.ID }) {
			places = append(places, Place{Label: session.Label, Session: session.ID, Whole: true})
		}
	}
	return places
}

func addPaneToPlaces(places []Place, p Pane) []Place {
	i := slices.IndexFunc(places, func(pl Place) bool { return pl.Session == p.Session && pl.Label == p.place() })
	if i < 0 {
		places = append(places, Place{Label: p.place(), Session: p.Session, Named: p.place() != p.Label})
		i = len(places) - 1
	}
	pl := &places[i]
	if p.Tab != "" && !slices.Contains(pl.Tabs, p.Tab) {
		pl.Tabs = append(pl.Tabs, p.Tab)
	}
	if p.Landing || pl.Tab == "" {
		pl.Tab = p.Tab
	}
	return places
}

// Find is the place labeled label, and false when there is none.
func (s Snapshot) Find(label string) (Place, bool) {
	places := s.Places()
	i := slices.IndexFunc(places, func(p Place) bool { return p.Label == label })
	if i < 0 {
		return Place{}, false
	}
	return places[i], true
}

// Session is the ID of the session labeled label, and false when there is
// none.
func (s Snapshot) Session(label string) (string, bool) {
	i := slices.IndexFunc(s.Sessions, func(session Session) bool { return session.Label == label })
	if i < 0 {
		return "", false
	}
	return s.Sessions[i].ID, true
}

// Landing is the pane going to the place lands on.
func (s Snapshot) Landing(pl Place) (Pane, bool) {
	i := slices.IndexFunc(s.Panes, func(p Pane) bool {
		return p.Session == pl.Session && (pl.Tab == "" && p.Landing || pl.Tab != "" && p.Tab == pl.Tab && p.Focused)
	})
	if i < 0 {
		return Pane{}, false
	}
	return s.Panes[i], true
}

// Statuses is each place's most urgent status, by its label.
func (s Snapshot) Statuses() map[string]Status {
	states := map[string]Status{}
	for _, p := range s.Panes {
		if cur, ok := states[p.place()]; !ok || p.Status < cur {
			states[p.place()] = p.Status
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
	// Actions, each on a session, place or pane that a Snapshot gave, or
	// that Create or CreateTab made.
	Create(label, dir string, panes []layout.Pane) (Place, error)            // a session labeled label running panes in dir
	CreateTab(session, name, dir string, panes []layout.Pane) (Place, error) // a tab of session named name, or unnamed when name is "", running panes in dir
	Show(p Place) error                                                      // shows the place's session and selects its tab
	Focus(p Pane) error                                                      // shows the pane's session and tab, with the pane focused
	Tab(p Place, dir string, args ...string) (Place, error)                  // a new tab of the place running args, which closes when they exit, as a place to Show
	Kill(p Place) error                                                      // closes the place's tabs, or its session when it is Whole
	Capture(p Pane) (string, error)                                          // the pane's text, with its colors
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

// Find is the place labeled label, and false when there is none.
func Find(b Backend, label string) (Place, bool, error) {
	s, err := b.Snapshot()
	p, ok := s.Find(label)
	return p, ok, err
}

// Label names a folder's place: PARENT/FOLDER, or just FOLDER when the
// folder is home, directly under home, or at the filesystem root. Worktrees
// under ~/worktrees/PROJECT/NAME get PROJECT/NAME by the same rule. tmux
// turns dots and colons into underscores, so Label does too and a place has
// one label in either.
func Label(dir, home string) string {
	dir = filepath.Clean(dir)
	label := filepath.Base(dir)
	parent := filepath.Dir(dir)
	if home != "" {
		home = filepath.Clean(home)
	}
	if dir != home && parent != home && parent != dir && parent != "." && parent != string(filepath.Separator) {
		label = filepath.Base(parent) + "/" + label
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

func run(name string, args ...string) (string, error) {
	return output(exec.Command(name, args...)) //nolint:gosec // callers pass fixed mux binary names ("rex" or "tmux")
}

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
