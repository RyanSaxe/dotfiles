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

	"workspace/kitty"
	"workspace/layout"
)

// Tmux is the tmux server, which the program may or may not run inside.
type Tmux struct {
	inside bool
	term   string
}

// tmux runs a tmux command. -u has it write UTF-8 whatever the locale, since
// without a UTF-8 locale, as under launchd, it prints each tab and non-ASCII
// character as an underscore.
func tmux(args ...string) (string, error) { return run("tmux", append([]string{"-u"}, args...)...) }

// paneFormat is what Snapshot reads of each pane. The title goes last,
// since a program can put a tab in it.
const paneFormat = "#{session_name}\t#{window_active}#{pane_active}\t#{pane_id}\t#{@ws}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_title}"

// Snapshot reads every pane with one list-panes. tmux has no program
// status, so every pane is Open, with no app or time.
func (Tmux) Snapshot() (Snapshot, error) {
	out, err := tmux("list-panes", "-a", "-F", paneFormat)
	if err != nil && (strings.Contains(err.Error(), "no server running") || strings.Contains(err.Error(), "error connecting")) {
		return Snapshot{}, nil
	}
	var s Snapshot
	for line := range strings.SplitSeq(out, "\n") {
		f := strings.SplitN(line, "\t", 7)
		if len(f) < 7 {
			continue
		}
		id := "=" + f[0] // = matches the name exactly
		if !slices.ContainsFunc(s.Sessions, func(s Session) bool { return s.ID == id }) {
			s.Sessions = append(s.Sessions, Session{id, f[0]})
		}
		s.Panes = append(s.Panes, Pane{Session: id, Label: f[0], ID: f[2], Landing: f[1] == "11", Agent: f[3] == "agent",
			Program: f[4], Folder: f[5], Status: Open, Title: f[6]})
	}
	return s, err
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

// Show switches this tmux client to the session, or attaches this terminal
// to it when the program runs outside tmux.
func (t Tmux) Show(id string) error {
	if t.inside {
		_, err := tmux("switch-client", "-t", id)
		return err
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

func (Tmux) Focus(p Pane) error {
	_, err := tmux("select-window", "-t", p.ID, ";", "select-pane", "-t", p.ID)
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
