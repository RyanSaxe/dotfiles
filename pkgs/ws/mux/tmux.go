package mux

import (
	"cmp"
	"fmt"
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

// paneFormat is what Snapshot reads of each pane. The title goes last,
// since a program can put a tab in it.
const paneFormat = "#{session_name}\t#{window_active}#{pane_active}\t#{pane_id}\t#{@ws}\t#{pane_current_command}\t#{pane_current_path}\t" +
	"#{@ws_status}\t#{@ws_app}\t#{@ws_pid}\t#{@ws_since}\t#{pane_title}"

// Snapshot reads every pane with one list-panes. tmux drops the escape
// sequence agents report their status to Rex with, so an agent's hooks
// record it on the agent's pane instead, in four pane options: @ws_status
// (working, blocked, done or error), @ws_app, @ws_pid (the agent's process)
// and @ws_since (when, in Unix seconds). A status counts only while that
// process runs, so the pane of an agent that crashed reads Open.
func (Tmux) Snapshot() (Snapshot, error) {
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
		p := Pane{Session: id, Label: f[0], ID: f[2], Landing: f[1] == "11", Agent: f[3] == "agent",
			Program: f[4], Folder: f[5], Status: Open, Title: f[10]}
		if status, ok := ParseStatus(f[6]); ok && running(f[8]) {
			p.Status, p.App = status, f[7]
			if since, err := strconv.ParseInt(f[9], 10, 64); err == nil {
				p.Updated = time.Unix(since, 0)
			}
		}
		s.Panes = append(s.Panes, p)
	}
	return s, err
}

// running says whether the process pid still runs. Signal 0 checks that
// without sending anything.
func running(pid string) bool {
	n, err := strconv.Atoi(pid)
	return err == nil && n > 0 && syscall.Kill(n, 0) != syscall.ESRCH
}

// Follow calls changed every few seconds and never returns, since tmux
// tells no one when a pane's options change. A Snapshot costs one
// list-panes, about 11 ms.
func (Tmux) Follow(changed func()) {
	for {
		changed()
		time.Sleep(3 * time.Second)
	}
}

func (Tmux) Create(label, dir string, panes []layout.Pane) (string, error) {
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
		if p.Agent && err == nil {
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

// Show switches the client to the session. Outside tmux with no Client, it
// attaches this terminal to the session instead.
func (t Tmux) Show(id string) error {
	if t.inside || t.Client != "" {
		return t.switchTo(id)
	}
	bin, err := exec.LookPath("tmux")
	if err != nil {
		return err
	}
	return syscall.Exec(bin, []string{"tmux", "attach-session", "-t", id}, os.Environ())
}

func (Tmux) Tab(id, dir string, args ...string) error {
	_, err := tmux(append([]string{"new-window", "-t", id + ":", "-c", dir, "--"}, args...)...)
	return err
}

func (Tmux) Send(id, text string) error {
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

func (Tmux) Kill(id string) error {
	_, err := tmux("kill-session", "-t", id)
	return err
}

// Focus switches the client to the pane's session, window and pane.
func (t Tmux) Focus(p Pane) error { return t.switchTo(p.ID) }

// switchTo switches the client to a session or a pane: Client when it's
// set, and otherwise the client of the pane the program runs in.
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
