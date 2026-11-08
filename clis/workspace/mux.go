package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/BurntSushi/toml"
)

// A backend is the multiplexer holding sessions. Each session is labeled
// after its folder, and the pane running the agent is marked "agent" (a Rex
// block label, a tmux pane option), so ws finds both again without keeping
// state of its own.
type backend interface {
	sessions() ([]session, error)
	create(label, dir string, panes []pane) (id string, err error)
	show(id string) error
	send(id, text string) error
	kill(id string) error
}

type session struct{ id, label string }

var (
	inTmux = os.Getenv("TMUX") != ""
	inRex  = os.Getenv("REX_BLOCK") != "" && !inTmux
)

// mux is Rex inside Rex and tmux otherwise. Outside both, tmux sessions
// still show up in lists and are what `ws open` starts.
func mux() backend {
	if inRex {
		return rexMux{}
	}
	return tmuxMux{}
}

func find(m backend, label string) (string, error) {
	ss, err := m.sessions()
	for _, s := range ss {
		if s.label == label {
			return s.id, nil
		}
	}
	return "", err
}

// labelFor names a folder's session: PROJECT/NAME for a worktree and the
// folder's name otherwise. tmux turns dots and colons into underscores, so
// ws does too and finds a session by the same label in either backend.
func labelFor(dir string) string {
	label := filepath.Base(dir)
	if rel, err := filepath.Rel(worktreeRoot, dir); err == nil && !strings.HasPrefix(rel, "..") && strings.Count(rel, "/") == 1 {
		label = rel
	}
	return strings.NewReplacer(".", "_", ":", "_").Replace(label)
}

type pane struct {
	Run   string
	Split string
	Size  int
	Focus bool
	agent bool
}

const agentLayout = `
[[pane]]
run = "{agent} {prompt}"
focus = true

[[pane]]
split = "right"
size = 35
`

// loadLayout reads a layout and fills in its placeholders. Each pane after
// the first splits the one before it, taking size percent of the space.
func loadLayout(name string, vars map[string]string) ([]pane, error) {
	data, err := os.ReadFile(filepath.Join(home, ".config", "ws", "layouts", name+".toml"))
	if errors.Is(err, os.ErrNotExist) && name == "agent" {
		data, err = []byte(agentLayout), nil
	}
	var l struct{ Pane []pane }
	if err == nil {
		var md toml.MetaData
		if md, err = toml.Decode(string(data), &l); err == nil && len(md.Undecoded()) > 0 {
			err = fmt.Errorf("unknown key %s", md.Undecoded()[0])
		}
	}
	if err == nil && len(l.Pane) == 0 {
		err = errors.New("it has no [[pane]]")
	}
	var pairs []string
	for k, v := range vars {
		pairs = append(pairs, k, quote(v))
	}
	fill := strings.NewReplacer(pairs...)
	for i := range l.Pane {
		p := &l.Pane[i]
		p.agent, p.Run = strings.Contains(p.Run, "{agent}"), strings.TrimSpace(fill.Replace(p.Run))
		p.Split, p.Size = cmp.Or(p.Split, "right"), cmp.Or(p.Size, 50)
		if !slices.Contains([]string{"right", "left", "above", "below"}, p.Split) && err == nil {
			err = fmt.Errorf("split %q is not right, left, above or below", p.Split)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("layout %s: %w", name, err)
	}
	return l.Pane, nil
}

// quote makes a word safe to type into the shell, leaving plain words bare
// so the typed command reads the way a person would type it.
func quote(s string) string {
	if strings.Trim(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@%+,") == "" {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// Panes start the login shell and ws types each command into it, so the
// shell's own functions apply. The claude and codex functions add flags.
type rexMux struct{}

func rex(args ...string) (string, error) { return runIn("", "rex", args...) }

func rexJSON(v any, args ...string) error {
	out, err := rex(args...)
	if err == nil {
		err = json.Unmarshal([]byte(out), v)
	}
	return err
}

func (rexMux) sessions() ([]session, error) {
	var ls struct {
		Sessions []struct {
			ID    string `json:"session_id"`
			Label string
		}
	}
	err := rexJSON(&ls, "ls", "--json")
	ss := make([]session, len(ls.Sessions))
	for i, s := range ls.Sessions {
		ss[i] = session{s.ID, s.Label}
	}
	return ss, err
}

func (rexMux) create(label, dir string, panes []pane) (string, error) {
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
		if p.agent {
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

// show switches a Rex app to a session, trying each viewer in turn because
// a client that created a pane stays its owner after it disconnects.
func (rexMux) show(id string) error {
	var err error
	for _, c := range viewers() {
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

// viewers lists the clients that may be showing this terminal: --client,
// else the owner whose size it follows and then each client that asked for
// a size, newest first, and last "" for Rex's own pick of the one app.
func viewers() []string {
	if client != "" {
		return []string{client}
	}
	var size struct {
		Owner   string
		Desired []struct {
			ID string `json:"client_id"`
		}
	}
	rexJSON(&size, "block", "call", "-s", os.Getenv("REX_SESSION"), "-b", os.Getenv("REX_BLOCK"), "size")
	cs := []string{size.Owner}
	for _, d := range size.Desired {
		cs = append(cs, d.ID)
	}
	return append(slices.Compact(slices.DeleteFunc(cs, func(c string) bool { return c == "" })), "")
}

func (rexMux) send(id, text string) error {
	_, err := rex("send", "-s", id, "-b", "agent", "--", text)
	if err == nil {
		_, err = rex("send-key", "-s", id, "-b", "agent", "enter")
	}
	return err
}

func (rexMux) kill(id string) error {
	_, err := rex("kill", id)
	return err
}

type terminal struct {
	session, label, block string
	state, app, cwd       string // state is "" when the program reports no status
	updated               time.Time
}

// rexTerminals lists every Rex terminal with the status its program
// reports, asking the server about each one in parallel.
func rexTerminals() ([]terminal, error) {
	ss, err := rexMux{}.sessions()
	var (
		mu  sync.Mutex
		wg  sync.WaitGroup
		out []terminal
	)
	for _, s := range ss {
		wg.Go(func() {
			var ls struct {
				Blocks []struct {
					ID      string `json:"block_id"`
					Creator string `json:"creator_name"`
				}
			}
			rexJSON(&ls, "block", "ls", "-s", s.id, "--json")
			for _, b := range ls.Blocks {
				if b.Creator != "com.superlogical.terminal" {
					continue
				}
				wg.Go(func() {
					t := terminal{session: s.id, label: s.label, block: b.ID}
					var status struct {
						Records []struct {
							ID, State, App string
							Updated        time.Time `json:"updated_at"`
						}
					}
					rexJSON(&status, "block", "call", "-s", s.id, "-b", b.ID, "program_status")
					// A record with no id is the program itself, and the others its parts.
					for _, r := range status.Records {
						if r.ID == "" {
							t.state, t.app, t.updated = r.State, r.App, r.Updated
						}
					}
					var proc struct{ Foreground struct{ Cwd string } }
					if t.state != "" && rexJSON(&proc, "block", "call", "-s", s.id, "-b", b.ID, "process") == nil {
						t.cwd = proc.Foreground.Cwd
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

// rank orders statuses by how soon they need a person.
func rank(state string) int {
	if i := slices.Index([]string{"blocked", "error", "done", "working", "idle"}, state); i >= 0 {
		return i
	}
	return 5
}

// agentStates maps each session's label to the most urgent status its
// programs report, or "open". tmux has no program status, so every tmux
// session is "open".
func agentStates() map[string]string {
	states := map[string]string{}
	if !inRex {
		ss, _ := tmuxMux{}.sessions()
		for _, s := range ss {
			states[s.label] = "open"
		}
		return states
	}
	ts, _ := rexTerminals()
	for _, t := range ts {
		if cur, ok := states[t.label]; !ok || rank(t.state) < rank(cur) {
			states[t.label] = cmp.Or(t.state, "open")
		}
	}
	return states
}

type tmuxMux struct{}

func tmux(args ...string) (string, error) { return runIn("", "tmux", args...) }

func (tmuxMux) sessions() ([]session, error) {
	out, err := tmux("list-sessions", "-F", "#{session_name}")
	if err != nil && (strings.Contains(err.Error(), "no server running") || strings.Contains(err.Error(), "error connecting")) {
		return nil, nil
	}
	var ss []session
	for name := range strings.SplitSeq(out, "\n") {
		if name != "" {
			ss = append(ss, session{"=" + name, name}) // = matches the name exactly
		}
	}
	return ss, err
}

func (tmuxMux) create(label, dir string, panes []pane) (string, error) {
	first, err := tmux("new-session", "-d", "-s", label, "-c", dir, "-P", "-F", "#{pane_id}")
	if err != nil {
		return "", err
	}
	ids := []string{first}
	for _, p := range panes[1:] {
		side := map[string]string{"right": "-h", "left": "-hb", "below": "-v", "above": "-vb"}[p.Split]
		id, err := tmux("split-window", side, "-d", "-t", ids[len(ids)-1], "-c", dir, "-l", strconv.Itoa(p.Size)+"%", "-P", "-F", "#{pane_id}")
		if err != nil {
			return "=" + label, err
		}
		ids = append(ids, id)
	}
	for i, p := range panes {
		if p.agent && err == nil {
			_, err = tmux("set-option", "-p", "-t", ids[i], "@ws", "agent")
		}
		if p.Run != "" && err == nil {
			err = tmuxType(ids[i], p.Run)
		}
		if p.Focus && err == nil {
			_, err = tmux("select-pane", "-t", ids[i])
		}
	}
	return "=" + label, err
}

// show switches this tmux client to the session, or attaches this terminal
// to it when ws runs outside tmux.
func (tmuxMux) show(id string) error {
	if inTmux {
		_, err := tmux("switch-client", "-t", id)
		return err
	}
	bin, err := exec.LookPath("tmux")
	if err != nil {
		return err
	}
	return syscall.Exec(bin, []string{"tmux", "attach-session", "-t", id}, os.Environ())
}

func (tmuxMux) send(id, text string) error {
	out, err := tmux("list-panes", "-s", "-t", id, "-F", "#{pane_id} #{@ws}")
	for line := range strings.SplitSeq(out, "\n") {
		if pane, mark, _ := strings.Cut(line, " "); mark == "agent" {
			return tmuxType(pane, text)
		}
	}
	return cmp.Or(err, fmt.Errorf("session %s has no agent pane", strings.TrimPrefix(id, "=")))
}

func tmuxType(pane, text string) error {
	_, err := tmux("send-keys", "-t", pane, "-l", "--", text)
	if err == nil {
		_, err = tmux("send-keys", "-t", pane, "Enter")
	}
	return err
}

func (tmuxMux) kill(id string) error {
	_, err := tmux("kill-session", "-t", id)
	return err
}
