package mux

import (
	"bufio"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"time"

	"workspace/kitty"
	"workspace/layout"
)

// Rex is a Rex server. Panes start the login shell and commands are typed
// into it, so the shell's own functions apply. Client is the app to switch,
// when it's known, and the rest is the terminal the program runs in.
//
// Shown and Seen are what you've looked at that the server can't tell a
// Snapshot: the label of the session Rex's window shows, "" when the caller
// doesn't know, and the failed or done records you were looking at when they
// came in, each by its pane's ID and its time.
type Rex struct {
	Client               string
	Shown                string
	Seen                 map[string]time.Time
	session, block, term string
}

// rex never starts a server: it only works with the one Rex already runs.
func rex(args ...string) (string, error) {
	return run("rex", append([]string{"--autostart=false"}, args...)...)
}

func rexJSON(v any, args ...string) error {
	out, err := rex(args...)
	if err == nil {
		err = json.Unmarshal([]byte(out), v)
	}
	return err
}

func (Rex) Create(label, dir string, panes []layout.Pane) (Place, error) {
	var made struct {
		ID      string `json:"session_id"`
		Windows []struct {
			Blocks []string `json:"block_ids"`
		} `json:"initial_windows"`
	}
	if err := rexJSON(&made, "new", label, "-c", dir, "--json"); err != nil {
		return Place{}, err
	}
	return Place{Label: label, Session: made.ID, Whole: true}, rexLayOut(made.ID, made.Windows[0].Blocks[0], dir, panes)
}

// CreateTab leaves the session's active tab as it is, until a pane in the
// layout takes the focus or Show selects the tab.
func (Rex) CreateTab(session, name, dir string, panes []layout.Pane) (Place, error) {
	args := []string{"window", "new", "-s", session}
	if name != "" {
		args = append(args, name)
	}
	var made struct {
		Window string   `json:"window_id"`
		Blocks []string `json:"block_ids"`
	}
	if err := rexJSON(&made, append(args, "-c", dir, "--focus=false", "--json")...); err != nil {
		return Place{}, err
	}
	p := Place{Label: name, Session: session, Tab: made.Window, Tabs: []string{made.Window}, Named: name != ""}
	return p, rexLayOut(session, made.Blocks[0], dir, panes)
}

// rexLayOut splits session's block first into panes and types each one's
// command.
func rexLayOut(s, first, dir string, panes []layout.Pane) error {
	blocks := []string{first}
	for _, p := range panes[1:] {
		var split struct {
			Blocks []string `json:"block_ids"`
		}
		if err := rexJSON(&split, "split", "-s", s, "-b", blocks[len(blocks)-1], "--split", p.Split,
			"--ratio", strconv.Itoa(p.Size), "-c", dir, "--focus=false", "--json"); err != nil {
			return err
		}
		blocks = append(blocks, split.Blocks[0])
	}
	var err error
	do := func(args ...string) {
		if err == nil {
			_, err = rex(args...)
		}
	}
	for i, p := range panes {
		if p.Run != "" {
			do("send", "-s", s, "-b", blocks[i], "--", p.Run)
			do("send-key", "-s", s, "-b", blocks[i], "enter")
		}
		// The first pane has the focus already, and a focus call makes its
		// tab the session's active one, which a tab made in the background
		// must not become.
		if p.Focus && i > 0 {
			do("focus", "-s", s, blocks[i])
		}
	}
	return err
}

// Show switches a Rex app to the place's session and selects its tab.
func (r Rex) Show(p Place) error { return r.show(p.Session, p.Tab) }

// show switches a Rex app to a session, and to one of its tabs when window
// isn't "", trying each viewer in turn because a client that created a pane
// stays its owner after it disconnects.
func (r Rex) show(session, window string) error {
	selection := []string{"do", "session.select", "session_id=" + session}
	if window != "" {
		selection = append(selection, "window_id="+window)
	}
	var err error
	for _, c := range r.viewers() {
		args := selection
		if c != "" {
			args = append([]string{"-C", c}, selection...)
		}
		if _, err = rex(args...); err == nil {
			return nil
		}
	}
	return err
}

// viewers lists the clients that may be showing this terminal: Client,
// else the owner whose size it follows and then each client that asked for
// a size, newest first, and last "" for Rex's own pick of the one app.
func (r Rex) viewers() []string {
	if r.Client != "" {
		return []string{r.Client}
	}
	var size struct {
		Owner   string
		Desired []struct {
			ID string `json:"client_id"`
		}
	}
	rexJSON(&size, "block", "call", "-s", r.session, "-b", r.block, "size")
	cs := []string{size.Owner}
	for _, d := range size.Desired {
		cs = append(cs, d.ID)
	}
	return append(slices.Compact(slices.DeleteFunc(cs, func(c string) bool { return c == "" })), "")
}

// Tab names the tab after the place when the place's tabs are named, so it
// is one of them, and makes it in the background, as CreateTab does.
func (Rex) Tab(p Place, dir string, args ...string) (Place, error) {
	window := []string{"window", "new", "-s", p.Session}
	if p.Named {
		window = append(window, p.Label)
	}
	var made struct {
		Window string `json:"window_id"`
	}
	err := rexJSON(&made, append(append(window, "-c", dir, "--focus=false", "--json", "--"), args...)...)
	return Place{Label: p.Label, Session: p.Session, Tab: made.Window, Tabs: []string{made.Window}, Named: p.Named}, err
}

// Kill closes the tab this program runs in last, since closing it ends the
// program, and rex closes the tabs it's given one at a time.
func (r Rex) Kill(p Place) error {
	if p.Whole {
		_, err := rex("kill", p.Session)
		return err
	}
	var view struct {
		Windows []struct {
			ID     string `json:"window_id"`
			Layers []struct {
				Blocks []struct {
					ID string `json:"block_id"`
				}
			}
		}
	}
	if err := rexJSON(&view, "window", "ls", "-s", p.Session, "--json"); err != nil {
		return err
	}
	own := "" // the tab this program runs in, floats such as a popup included
	for _, w := range view.Windows {
		for _, l := range w.Layers {
			for _, b := range l.Blocks {
				if b.ID == r.block {
					own = w.ID
				}
			}
		}
	}
	tabs := slices.Clone(p.Tabs)
	if i := slices.Index(tabs, own); i >= 0 {
		tabs = append(slices.Delete(tabs, i, i+1), own)
	}
	_, err := rex(append([]string{"window", "close", "-s", p.Session}, tabs...)...)
	return err
}

//go:embed snapshot.lua
var snapshotScript string

// Snapshot reads every session and terminal with snapshot.lua, in one call
// to the server.
func (r Rex) Snapshot() (Snapshot, error) {
	var read struct {
		Sessions luaList[Session]
		Panes    luaList[struct {
			Session, Label, ID, Tab, Program, Folder, Status, App, Title string
			TabName                                                      string `json:"tab_name"`
			Focused, Landing                                             bool
			Updated                                                      time.Time
			Shown                                                        luaList[time.Time]
		}]
	}
	cmd := exec.Command("rex", "--autostart=false", "do", "-")
	cmd.Stdin = strings.NewReader(snapshotScript)
	out, err := output(cmd)
	if err == nil {
		err = json.Unmarshal([]byte(out), &read)
	}
	s := Snapshot{Sessions: read.Sessions}
	for _, p := range read.Panes {
		status, _ := ParseStatus(p.Status)
		pane := Pane{Session: p.Session, Label: p.Label, ID: p.ID, Tab: p.Tab, TabName: p.TabName, Focused: p.Focused, Landing: p.Landing,
			Program: p.Program, Folder: p.Folder, Status: status, App: p.App, Title: p.Title, Updated: p.Updated}
		pane.NeedsYou = r.needsYou(pane, p.Shown, r.Shown != "" && p.Label == r.Shown && p.Landing)
		s.Panes = append(s.Panes, pane)
	}
	return s, err
}

// needsYou says whether a pane's agent needs you and you haven't looked at
// the pane since. A blocked agent needs you until it reports something else,
// and a failed or done one until an app shows its pane. Rex doesn't expose
// the app's seen state yet, so the app's size requests stand in for it: an
// app asks for a pane's size each time it shows the pane, so a failed or
// done record newer than every request is unseen. The pane you're looking at
// needs nothing. Neither does a record that came while you looked, which
// Seen lists, since its pane's last request came before it.
func (r Rex) needsYou(p Pane, shown []time.Time, looking bool) bool {
	switch {
	case looking:
		return false
	case p.Status == Blocked:
		return true
	case p.Status == Error || p.Status == Done:
		seen := r.Seen[p.ID].Equal(p.Updated) || slices.ContainsFunc(shown, func(t time.Time) bool { return !t.Before(p.Updated) })
		return !seen
	}
	return false
}

// A luaList is a list a Lua script returns, which reads as {} when it's
// empty, since Lua has one kind of table for lists and objects.
type luaList[T any] []T

func (l *luaList[T]) UnmarshalJSON(data []byte) error {
	if string(data) == "{}" {
		*l = nil
		return nil
	}
	return json.Unmarshal(data, (*[]T)(l))
}

//go:embed focus.lua
var focusScript string

// Focus shows a pane with focus.lua, in one call to the server, trying each
// viewer in turn as show does.
func (r Rex) Focus(p Pane) error {
	var err error
	for _, c := range r.viewers() {
		args := []string{"do", "-", "session_id=" + p.Session, "block_id=" + p.ID}
		if c != "" {
			args = append([]string{"-C", c}, args...)
		}
		cmd := exec.Command("rex", append([]string{"--autostart=false"}, args...)...)
		cmd.Stdin = strings.NewReader(focusScript)
		if _, err = output(cmd); err == nil {
			return nil
		}
	}
	return err
}

func (Rex) Capture(p Pane) (string, error) {
	return rex("capture", "-s", p.Session, "-b", p.ID, "--format", "vt", "--trim")
}

func (Rex) Inside() bool { return true }

func (r Rex) Current() (string, error) { return r.session, nil }

func (r Rex) Images() kitty.Terminal { return kitty.Terminal{Draws: draws(r.term)} }

// draws says whether a terminal program draws Kitty images.
func draws(term string) bool {
	switch term {
	case "ghostty", "kitty", "rex":
		return true
	}
	return false
}

// A Binding is a key the server's config binds: the keys pressed in turn,
// the action they run with its arguments, and the config line that binds it.
type Binding struct {
	Keys   []string
	Action string
	Args   map[string]any
	Source string
}

// Keymap is the keys the server's config binds, the top of each key's stack
// first, and the titles of the actions Client and the server offer.
func (r Rex) Keymap() ([]Binding, map[string]string, error) {
	type action struct{ Name, Title string }
	var keymap struct {
		Bindings []Binding
		Actions  []action // the server's
	}
	if err := rexJSON(&keymap, "keymap", "--json"); err != nil {
		return nil, nil, err
	}
	// When the app can't be asked, such as after it quit, its actions go by
	// their names.
	var app struct{ Actions []action }
	if r.Client != "" {
		rexJSON(&app, "-C", r.Client, "actions", "--json")
	}
	titles := map[string]string{}
	for _, a := range slices.Concat(app.Actions, keymap.Actions) {
		if a.Title != "" {
			titles[a.Name] = a.Title
		}
	}
	return keymap.Bindings, titles, nil
}

// App is the Rex app on this Mac, the client a key outside every terminal
// means.
func (Rex) App() (string, error) {
	var ls struct {
		Clients []struct {
			ID    string `json:"client_id"`
			State string `json:"connection_state"`
			Info  struct{ Kind, Platform string }
		}
	}
	if err := rexJSON(&ls, "client", "ls", "--json"); err != nil {
		return "", err
	}
	for _, c := range ls.Clients {
		if c.Info.Kind == "app" && c.Info.Platform == "macos" && c.State == "connected" {
			return c.ID, nil
		}
	}
	return "", errors.New("the Rex app is not connected")
}

// Follow calls changed once at the start and then for every event that can
// change whether an agent needs you: a report, a removed report, an app
// showing a pane, which asks for its size, a session's view changing, a
// closed pane or a closed session. It restarts the stream when the Rex
// server goes away, and never returns.
func (Rex) Follow(changed func()) {
	for {
		changed()
		cmd := exec.Command("rex", "--autostart=false", "events", "--all", "--json")
		out, err := cmd.StdoutPipe()
		if err == nil {
			err = cmd.Start()
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "ws: rex events:", err)
			time.Sleep(5 * time.Second)
			continue
		}
		lines := bufio.NewScanner(out)
		lines.Buffer(make([]byte, 1<<20), 1<<20)
		for lines.Scan() {
			var e struct {
				Type    string
				Payload struct {
					Event struct {
						Type    string
						Payload struct{ Name string }
					}
				}
			}
			if json.Unmarshal(lines.Bytes(), &e) != nil {
				continue
			}
			ev := e.Payload.Event
			if e.Type == "session_destroyed" || ev.Type == "block_closed" || ev.Type == "session_view_changed" ||
				ev.Type == "block_event" && (strings.HasPrefix(ev.Payload.Name, "program_status") || ev.Payload.Name == "size_changed") {
				changed()
			}
		}
		cmd.Wait()
		time.Sleep(5 * time.Second)
	}
}
