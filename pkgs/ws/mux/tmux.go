package mux

import (
	"cmp"
	"fmt"
	"os"
	"os/exec"
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

func tmux(args ...string) (string, error) { return run("tmux", args...) }

func (Tmux) Sessions() ([]Session, error) {
	out, err := tmux("list-sessions", "-F", "#{session_name}")
	if err != nil && (strings.Contains(err.Error(), "no server running") || strings.Contains(err.Error(), "error connecting")) {
		return nil, nil
	}
	var ss []Session
	for name := range strings.SplitSeq(out, "\n") {
		if name != "" {
			ss = append(ss, Session{"=" + name, name}) // = matches the name exactly
		}
	}
	return ss, err
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

// Capture reads the active pane of the session's current window.
func (Tmux) Capture(id string) (string, error) {
	return tmux("capture-pane", "-p", "-e", "-J", "-t", id+":")
}

// Landing is the program in the session's active pane, since tmux has no
// program status, and its folder.
func (Tmux) Landing(id string) Pane {
	out, _ := tmux("display-message", "-p", "-t", id+":", "#{pane_current_command}\t#{pane_current_path}")
	doing, folder, _ := strings.Cut(out, "\t")
	return Pane{Doing: doing, Folder: folder}
}

// Statuses is Open for every session, since tmux has no program status.
func (t Tmux) Statuses() map[string]Status {
	states := map[string]Status{}
	ss, _ := t.Sessions()
	for _, s := range ss {
		states[s.Label] = Open
	}
	return states
}

func (t Tmux) Inside() bool { return t.inside }

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
