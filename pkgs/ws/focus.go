package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"workspace/mux"
)

// AeroSpace's Cmd-Alt-A, T and R switch to the code workspace and run
// `ws focus`, which brings the terminal onto it and acts there: Rex when it's
// installed, and otherwise Ghostty on tmux.

const (
	rexBundle     = "com.superlogical.rex"
	ghosttyBundle = "com.mitchellh.ghostty"
	codeWorkspace = "code"
)

func focus(what string) error {
	if !slices.Contains([]string{"agent", "tasks", "reviews"}, what) {
		return fmt.Errorf("ws focus takes agent, tasks or reviews, not %q", what)
	}
	// open fails only when no app has the bundle ID. -g leaves the window
	// where it is, for bringToCode to move.
	if _, err := runIn("", "open", "-g", "-b", rexBundle); err != nil {
		return focusTmux(what)
	}
	if err := bringToCode(rexBundle); err != nil {
		return err
	}
	var client string
	err := waitFor(func() (err error) { client, err = (mux.Rex{}).App(); return err })
	if err != nil {
		return err
	}
	if what == "agent" {
		return jumpToAgent(client)
	}
	// Run from outside Rex, the popup action has no session or pane of its
	// own, so it gets the session the app shows and that session's pane.
	var session, block string
	err = waitFor(func() (err error) {
		if session, err = shownSession(); err == nil {
			block, err = focusedBlock(session)
		}
		return err
	})
	if err != nil {
		return err
	}
	_, err = runIn("", "rex", "-C", client, "do", "-s", session, "-b", block, "ws_pick", "name="+what)
	return err
}

// focusedBlock is the pane focused in a session's active window.
func focusedBlock(session string) (string, error) {
	out, err := runIn("", "rex", "session", "inspect", session, "--json")
	if err != nil {
		return "", err
	}
	var s struct {
		Active  string `json:"active_window_id"`
		Windows []struct {
			ID      string `json:"window_id"`
			Focused string `json:"focused_block_id"`
		}
	}
	if err := json.Unmarshal([]byte(out), &s); err != nil {
		return "", err
	}
	for _, w := range s.Windows {
		if w.ID == s.Active && w.Focused != "" {
			return w.Focused, nil
		}
	}
	return "", fmt.Errorf("session %s has no focused pane", session)
}

// shownSession is the session Rex's window shows. Rex reports no such
// thing, but the window's title ends with the session's label.
func shownSession() (string, error) {
	ws, err := appWindows(rexBundle)
	if err != nil {
		return "", err
	}
	w, ok := pickWindow(ws)
	i := strings.LastIndex(w.title, " - ")
	if !ok || i < 0 {
		return "", errors.New("Rex's window doesn't name a session")
	}
	label := w.title[i+len(" - "):]
	id, err := mux.Find(mux.Rex{}, label)
	if id == "" && err == nil {
		err = fmt.Errorf("no session is labeled %q", label)
	}
	return id, err
}

// focusTmux opens Tasks or Reviews as a popup in the tmux client used last,
// starting Ghostty on tmux's main session when no client is attached. tmux
// has no agent statuses, so agent only says that.
func focusTmux(what string) error {
	clients, _ := runIn("", "tmux", "list-clients", "-F", "#{client_activity} #{client_name}")
	client := newestClient(clients)
	if client == "" {
		if _, err := runIn("", "open", "-n", "-b", ghosttyBundle, "--args", "-e", "tmux", "new-session", "-A", "-s", "main"); err != nil {
			return err
		}
		err := waitFor(func() error {
			clients, _ = runIn("", "tmux", "list-clients", "-F", "#{client_activity} #{client_name}")
			if client = newestClient(clients); client == "" {
				return errors.New("tmux didn't start in Ghostty")
			}
			return nil
		})
		if err != nil {
			return err
		}
	} else if err := bringToCode(ghosttyBundle); err != nil {
		return err
	}
	if what == "agent" {
		_, err := runIn("", "tmux", "display-message", "-c", client, "Agents report no status in tmux yet")
		return err
	}
	_, err := runIn("", "tmux", "display-popup", "-c", client, "-d", "#{pane_current_path}", "-h", "80%", "-w", "90%", "-E", "ws pick "+what)
	return err
}

// bringToCode focuses the app's window on the code workspace, moving one
// there when none is. An app with no window yet opens one on the focused
// workspace, which the key has already made the code workspace.
func bringToCode(bundle string) error {
	ws, err := appWindows(bundle)
	if err != nil {
		return err
	}
	w, ok := pickWindow(ws)
	if !ok {
		_, err := runIn("", "open", "-b", bundle)
		return err
	}
	if w.workspace != codeWorkspace {
		if _, err := runIn("", "aerospace", "move-node-to-workspace", "--window-id", w.id, codeWorkspace); err != nil {
			return err
		}
	}
	_, err = runIn("", "aerospace", "focus", "--window-id", w.id)
	return err
}

type window struct{ id, workspace, title string }

// appWindows lists an app's windows on every monitor, as AeroSpace sees
// them.
func appWindows(bundle string) ([]window, error) {
	list, err := runIn("", "aerospace", "list-windows", "--monitor", "all", "--app-bundle-id", bundle, "--format", "%{window-id}|%{workspace}|%{window-title}")
	var ws []window
	for line := range strings.SplitSeq(list, "\n") {
		if parts := strings.SplitN(line, "|", 3); len(parts) == 3 {
			ws = append(ws, window{parts[0], parts[1], parts[2]})
		}
	}
	return ws, err
}

// pickWindow is the window to bring forward: the first on the code
// workspace, else the first that isn't a Settings window.
func pickWindow(ws []window) (window, bool) {
	ws = slices.DeleteFunc(ws, func(w window) bool { return strings.HasPrefix(w.title, "Settings") })
	if i := slices.IndexFunc(ws, func(w window) bool { return w.workspace == codeWorkspace }); i >= 0 {
		return ws[i], true
	}
	if len(ws) == 0 {
		return window{}, false
	}
	return ws[0], true
}

// newestClient is the tmux client with the latest activity, from
// list-clients' "ACTIVITY NAME" lines, or "" when none is attached.
func newestClient(list string) string {
	name, newest := "", -1
	for line := range strings.SplitSeq(list, "\n") {
		activity, client, ok := strings.Cut(line, " ")
		if n, err := strconv.Atoi(activity); ok && err == nil && n > newest {
			name, newest = client, n
		}
	}
	return name
}

// waitFor retries try for up to 15 seconds, while an app starts.
func waitFor(try func() error) error {
	deadline := time.Now().Add(15 * time.Second)
	for {
		err := try()
		if err == nil || time.Now().After(deadline) {
			return err
		}
		time.Sleep(250 * time.Millisecond)
	}
}
