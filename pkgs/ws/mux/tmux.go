package mux

import (
	"cmp"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"workspace/kitty"
	"workspace/layout"
)

// Tmux is the tmux server, which the program may or may not run inside.
// Client is the client Show and Focus switch when the program runs outside
// tmux, as from a key bound outside every terminal.
type Tmux struct {
	Client string
	inside bool
	term   string
}

// tmux runs a tmux command. -u has it write UTF-8 whatever the locale, since
// without a UTF-8 locale, as under launchd, it prints each tab and non-ASCII
// character as an underscore.
func tmux(args ...string) (string, error) { return run("tmux", append([]string{"-u"}, args...)...) }

// paneFormat is what Snapshot reads of each pane. It reads a window's name
// only when someone named the window, which turns its automatic-rename off.
// The title goes last, since a program can put a tab in it.
const paneFormat = "#{session_name}\t#{window_active}#{pane_active}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t" +
	"#{window_bell_flag}\t#{window_activity}\t#{window_id}\t#{?automatic-rename,,#{window_name}}\t#{pane_title}"

// working is how recently an agent's window must have printed for the agent
// to count as working.
const working = 5 * time.Second

// Snapshot reads every pane with one list-panes, and the process table to
// find the panes an agent runs in. tmux has no program status, so what it
// tracks of an agent's window stands in for one: the agent works while the
// window prints, and needs you while the window's bell flag is up. tmux
// raises the flag when the bell rings in a window no client shows, and
// lowers it when a client switches to the window, so a bell you saw marks
// nothing.
func (Tmux) Snapshot() (Snapshot, error) {
	processes, err := readProcessTree()
	if err != nil {
		return Snapshot{}, err
	}
	out, err := tmux("list-panes", "-a", "-F", paneFormat)
	if err != nil && (strings.Contains(err.Error(), "no server running") || strings.Contains(err.Error(), "error connecting")) {
		return Snapshot{}, nil
	}
	var s Snapshot
	for line := range strings.SplitSeq(out, "\n") {
		f := strings.SplitN(line, "\t", 11)
		if len(f) < 11 {
			continue
		}
		id := "=" + f[0] // = matches the name exactly
		if !slices.ContainsFunc(s.Sessions, func(s Session) bool { return s.ID == id }) {
			s.Sessions = append(s.Sessions, Session{id, f[0]})
		}
		p := Pane{Session: id, Label: f[0], ID: f[2], Tab: f[8], TabName: f[9], Focused: strings.HasSuffix(f[1], "1"), Landing: f[1] == "11",
			Program: f[4], Folder: f[5], Status: Open, Title: f[10]}
		if pid, err := strconv.Atoi(f[3]); err == nil && processes.runsAgent(pid) {
			activity, _ := strconv.ParseInt(f[7], 10, 64)
			p.Updated = time.Unix(activity, 0)
			p.Status = Idle
			if time.Since(p.Updated) < working {
				p.Status = Working
			}
			p.NeedsYou = f[6] == "1"
		}
		s.Panes = append(s.Panes, p)
	}
	return s, err
}

// Follow calls changed every few seconds and never returns, since tmux tells
// no one when a window prints or rings. A Snapshot costs one list-panes,
// about 11 ms.
func (Tmux) Follow(changed func()) {
	for {
		changed()
		time.Sleep(3 * time.Second)
	}
}

func (Tmux) Create(label, dir string, panes []layout.Pane) (Place, error) {
	first, err := tmux("new-session", "-d", "-s", label, "-c", dir, "-P", "-F", "#{pane_id}")
	if err != nil {
		return Place{}, err
	}
	return Place{Label: label, Session: "=" + label, Whole: true}, tmuxLayOut(first, dir, panes)
}

// CreateTab makes the window in the background, so a client showing the
// session stays where it is until Show.
func (Tmux) CreateTab(session, name, dir string, panes []layout.Pane) (Place, error) {
	args := []string{"new-window", "-d", "-t", session + ":", "-c", dir, "-P", "-F", "#{window_id} #{pane_id}"}
	if name != "" {
		args = append(args, "-n", name)
	}
	out, err := tmux(args...)
	if err != nil {
		return Place{}, err
	}
	window, first, _ := strings.Cut(out, " ")
	p := Place{Label: name, Session: session, Tab: window, Tabs: []string{window}, Named: name != ""}
	return p, tmuxLayOut(first, dir, panes)
}

// tmuxLayOut splits the first pane into panes and types each one's command.
func tmuxLayOut(first, dir string, panes []layout.Pane) error {
	ids := []string{first}
	for _, p := range panes[1:] {
		side := map[string]string{"right": "-h", "left": "-hb", "below": "-v", "above": "-vb"}[p.Split]
		id, err := tmux("split-window", side, "-d", "-t", ids[len(ids)-1], "-c", dir, "-l", strconv.Itoa(p.Size)+"%", "-P", "-F", "#{pane_id}")
		if err != nil {
			return err
		}
		ids = append(ids, id)
	}
	var err error
	for i, p := range panes {
		if p.Run != "" && err == nil {
			err = tmuxType(ids[i], p.Run)
		}
		if p.Focus && err == nil {
			_, err = tmux("select-pane", "-t", ids[i])
		}
	}
	return err
}

// Show switches the client to the place's session and tab. Outside tmux
// with no Client, it selects the tab and attaches this terminal to the
// session instead.
func (t Tmux) Show(p Place) error {
	if t.inside || t.Client != "" {
		return t.switchTo(cmp.Or(p.Tab, p.Session))
	}
	if p.Tab != "" {
		if _, err := tmux("select-window", "-t", p.Tab); err != nil {
			return err
		}
	}
	bin, err := exec.LookPath("tmux")
	if err != nil {
		return err
	}
	return syscall.Exec(bin, []string{"tmux", "attach-session", "-t", p.Session}, os.Environ())
}

// Tab names the window after the place when the place's tabs are named, so
// it is one of them.
func (t Tmux) Tab(p Place, dir string, args ...string) error {
	window := []string{"new-window", "-t", p.Session + ":", "-c", dir, "-P", "-F", "#{window_id}"}
	if p.Named {
		window = append(window, "-n", p.Label)
	}
	id, err := tmux(append(append(window, "--"), args...)...)
	if err == nil && (t.inside || t.Client != "") {
		err = t.switchTo(id)
	}
	return err
}

func tmuxType(pane, text string) error {
	_, err := tmux("send-keys", "-t", pane, "-l", "--", text)
	if err == nil {
		_, err = tmux("send-keys", "-t", pane, "Enter")
	}
	return err
}

func (Tmux) Kill(p Place) error {
	if p.Whole {
		_, err := tmux("kill-session", "-t", p.Session)
		return err
	}
	for _, tab := range p.Tabs {
		if _, err := tmux("kill-window", "-t", tab); err != nil {
			return err
		}
	}
	return nil
}

// Focus switches the client to the pane's session, window and pane. Outside
// tmux with no Client, it selects the pane and attaches this terminal to its
// session instead.
func (t Tmux) Focus(p Pane) error {
	if t.inside || t.Client != "" {
		return t.switchTo(p.ID)
	}
	if _, err := tmux("select-window", "-t", p.ID, ";", "select-pane", "-t", p.ID); err != nil {
		return err
	}
	return t.Show(Place{Session: p.Session})
}

// switchTo switches the client to a session, window or pane: Client when
// it's set, and otherwise the client of the pane the program runs in.
func (t Tmux) switchTo(target string) error {
	args := []string{"switch-client", "-t", target}
	if t.Client != "" {
		args = append(args, "-c", t.Client)
	}
	_, err := tmux(args...)
	return err
}

func (Tmux) Capture(p Pane) (string, error) {
	return tmux("capture-pane", "-p", "-e", "-J", "-t", p.ID)
}

func (t Tmux) Inside() bool { return t.inside }

// Current is the session of the pane or popup the program runs in, which
// tmux names in the TMUX variable it gives both.
func (Tmux) Current() (string, error) {
	name, err := tmux("display-message", "-p", "#{session_name}")
	return "=" + name, err
}

// Images asks tmux which terminal it runs in, since tmux names itself in
// TERM_PROGRAM, and sends images through tmux to it.
func (t Tmux) Images() kitty.Terminal {
	term := t.term
	if t.inside {
		term, _ = tmux("display-message", "-p", "#{client_termtype}")
		term, _, _ = strings.Cut(strings.ToLower(term), " ")
	}
	return kitty.Terminal{Draws: draws(term), Tmux: t.inside}
}
