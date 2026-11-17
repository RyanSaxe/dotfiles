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
type Rex struct {
	Client               string
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

func (Rex) Create(label, dir string, panes []layout.Pane) (string, error) {
	var made struct {
		ID      string `json:"session_id"`
		Windows []struct {
			Blocks []string `json:"block_ids"`
		} `json:"initial_windows"`
	}
	if err := rexJSON(&made, "new", label, "-c", dir, "--json"); err != nil {
		return "", err
	}
	s, blocks := made.ID, made.Windows[0].Blocks[:1]
	for _, p := range panes[1:] {
		var split struct {
			Blocks []string `json:"block_ids"`
		}
		if err := rexJSON(&split, "split", "-s", s, "-b", blocks[len(blocks)-1], "--split", p.Split,
			"--ratio", strconv.Itoa(p.Size), "-c", dir, "--focus=false", "--json"); err != nil {
			return s, err
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
		if p.Agent {
			do("block", "rename", "-s", s, blocks[i], "agent")
		}
		if p.Run != "" {
			do("send", "-s", s, "-b", blocks[i], "--", p.Run)
			do("send-key", "-s", s, "-b", blocks[i], "enter")
		}
		if p.Focus {
			do("focus", "-s", s, blocks[i])
		}
	}
	return s, err
}

// Show switches a Rex app to a session.
func (r Rex) Show(id string) error { return r.show(id, "") }

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

// Tab brings the app to the tab it opens, since the app keeps showing its
// own tab when the server makes another one active.
func (r Rex) Tab(id, dir string, args ...string) error {
	var made struct {
		Window string `json:"window_id"`
	}
	if err := rexJSON(&made, append([]string{"run", "-s", id, "-c", dir, "--json", "--"}, args...)...); err != nil {
		return err
	}
	return r.show(id, made.Window)
}

func (Rex) Send(id, text string) error {
	_, err := rex("send", "-s", id, "-b", "agent", "--", text)
	if err == nil {
		_, err = rex("send-key", "-s", id, "-b", "agent", "enter")
	}
	return err
}

func (Rex) Kill(id string) error {
	_, err := rex("kill", id)
	return err
}

//go:embed snapshot.lua
var snapshotScript string

// Snapshot reads every session and terminal with snapshot.lua, in one call
// to the server.
func (Rex) Snapshot() (Snapshot, error) {
	var read struct {
		Sessions luaList[Session]
		Panes    luaList[struct {
			Session, Label, ID, Program, Folder, Status, App, Title string
			Landing, Agent                                          bool
			Updated                                                 time.Time
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
		s.Panes = append(s.Panes, Pane{Session: p.Session, Label: p.Label, ID: p.ID, Landing: p.Landing, Agent: p.Agent,
			Program: p.Program, Folder: p.Folder, Status: status, App: p.App, Title: p.Title, Updated: p.Updated})
	}
	return s, err
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

func (Rex) Focus(p Pane) error {
	_, err := rex("focus", "-s", p.Session, p.ID)
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

// PaneFolder is the folder of the program in one of this session's panes.
func (r Rex) PaneFolder(block string) string {
	var proc struct{ Foreground struct{ Cwd string } }
	rexJSON(&proc, "block", "call", "-s", r.session, "-b", block, "process")
	return proc.Foreground.Cwd
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
// change a status: a report, a removed report, a closed pane or a closed
// session. It restarts the stream when the Rex server goes away, and never
// returns.
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
			if e.Type == "session_destroyed" || ev.Type == "block_closed" ||
				ev.Type == "block_event" && strings.HasPrefix(ev.Payload.Name, "program_status") {
				changed()
			}
		}
		cmd.Wait()
		time.Sleep(5 * time.Second)
	}
}
