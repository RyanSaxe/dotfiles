package mux

import (
	"bufio"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"sync"
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

func (Rex) Sessions() ([]Session, error) {
	var ls struct {
		Sessions []struct {
			ID    string `json:"session_id"`
			Label string
		}
	}
	err := rexJSON(&ls, "ls", "--json")
	ss := make([]Session, len(ls.Sessions))
	for i, s := range ls.Sessions {
		ss[i] = Session{s.ID, s.Label}
	}
	return ss, err
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

// Show switches a Rex app to a session, trying each viewer in turn because
// a client that created a pane stays its owner after it disconnects.
func (r Rex) Show(id string) error {
	var err error
	for _, c := range r.viewers() {
		args := []string{"do", "session.select", "session_id=" + id}
		if c != "" {
			args = append([]string{"-C", c}, args...)
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

func (Rex) Tab(id, dir string, args ...string) error {
	_, err := rex(append([]string{"run", "-s", id, "-c", dir, "--"}, args...)...)
	return err
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

func (r Rex) Capture(id string) (string, error) {
	block, err := r.landing(id)
	if err != nil || block == "" {
		return "", err
	}
	return r.CaptureBlock(id, block)
}

// CaptureBlock is the text of one pane, with its colors.
func (Rex) CaptureBlock(session, block string) (string, error) {
	return rex("capture", "-s", session, "-b", block, "--format", "vt", "--trim")
}

func (r Rex) Landing(id string) Pane {
	block, err := r.landing(id)
	if err != nil || block == "" {
		return Pane{}
	}
	var proc struct{ Foreground struct{ Name, Cwd string } }
	done := make(chan struct{})
	go func() {
		rexJSON(&proc, "block", "call", "-s", id, "-b", block, "process")
		close(done)
	}()
	state := programStatus(id, block).State
	<-done
	return Pane{Doing: cmp.Or(state, proc.Foreground.Name), Folder: proc.Foreground.Cwd}
}

// landing is the pane a session shows, where going to it lands: the focused
// pane of its active tab, or the tab's first tiled pane when a float, such as
// a popup, has the focus.
func (Rex) landing(id string) (string, error) {
	var view struct {
		Active  string `json:"active_window_id"`
		Windows []struct {
			ID      string `json:"window_id"`
			Focused string `json:"focused_block_id"`
			Layers  []struct {
				Kind   string
				Blocks []struct {
					ID string `json:"block_id"`
				}
			}
		}
	}
	if err := rexJSON(&view, "session", "inspect", id, "--json"); err != nil {
		return "", err
	}
	for _, w := range view.Windows {
		if w.ID != view.Active {
			continue
		}
		for _, l := range w.Layers {
			if l.Kind != "tiled" || len(l.Blocks) == 0 {
				continue
			}
			block := l.Blocks[0].ID
			for _, b := range l.Blocks {
				if b.ID == w.Focused {
					block = b.ID
				}
			}
			return block, nil
		}
	}
	return "", nil
}

func (r Rex) Statuses() map[string]Status {
	states := map[string]Status{}
	ts, _ := r.Terminals()
	for _, t := range ts {
		if cur, ok := states[t.Label]; !ok || t.Status < cur {
			states[t.Label] = t.Status
		}
	}
	return states
}

func (Rex) Inside() bool { return true }

func (r Rex) Images() kitty.Terminal { return kitty.Terminal{Draws: draws(r.term)} }

// draws says whether a terminal program draws Kitty images.
func draws(term string) bool {
	switch term {
	case "ghostty", "kitty", "rex":
		return true
	}
	return false
}

type programState struct {
	ID, State, App string
	Updated        time.Time `json:"updated_at"`
}

// programStatus is what a terminal's program reports about itself. A record
// with no id is the program itself, and the others its parts.
func programStatus(session, block string) programState {
	var res struct{ Records []programState }
	rexJSON(&res, "block", "call", "-s", session, "-b", block, "program_status")
	for _, r := range res.Records {
		if r.ID == "" {
			return r
		}
	}
	return programState{}
}

// A Terminal is one Rex pane and what its program reports. Status is Open
// when the program reports nothing, and then App, Cwd and Title are empty.
type Terminal struct {
	Session, Label, Block string
	Status                Status
	App, Cwd              string
	Title                 string // what the program calls the terminal, such as an agent's task
	Updated               time.Time
}

// Terminals lists every Rex terminal with the status its program reports,
// asking the server about each one in parallel.
func (Rex) Terminals() ([]Terminal, error) {
	ss, err := Rex{}.Sessions()
	var (
		mu  sync.Mutex
		wg  sync.WaitGroup
		out []Terminal
	)
	for _, s := range ss {
		wg.Go(func() {
			var ls struct {
				Blocks []struct {
					ID      string `json:"block_id"`
					Creator string `json:"creator_name"`
				}
			}
			rexJSON(&ls, "block", "ls", "-s", s.ID, "--json")
			for _, b := range ls.Blocks {
				if b.Creator != "com.superlogical.terminal" {
					continue
				}
				wg.Go(func() {
					t := Terminal{Session: s.ID, Label: s.Label, Block: b.ID}
					st := programStatus(s.ID, b.ID)
					t.Status, _ = ParseStatus(st.State)
					if t.Status != Open {
						t.App, t.Updated = st.App, st.Updated
						var proc struct{ Foreground struct{ Cwd string } }
						var title struct{ Title string }
						if rexJSON(&proc, "block", "call", "-s", s.ID, "-b", b.ID, "process") == nil {
							t.Cwd = proc.Foreground.Cwd
						}
						if rexJSON(&title, "block", "call", "-s", s.ID, "-b", b.ID, "title") == nil {
							t.Title = title.Title
						}
					}
					mu.Lock()
					out = append(out, t)
					mu.Unlock()
				})
			}
		})
	}
	wg.Wait()
	return out, err
}

// Focus moves a session's focus to one of its panes.
func (Rex) Focus(session, block string) error {
	_, err := rex("focus", "-s", session, block)
	return err
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
