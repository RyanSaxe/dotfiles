package main

import (
	"bufio"
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
	"workspace/mux"
)

// AeroSpace's Cmd-Alt-A, T and R run `ws focus`, which checks what had focus,
// switches to the code workspace, brings the terminal onto it and acts there:
// Rex when it's installed, and otherwise Ghostty on tmux.

const (
	rexBundle     = "com.superlogical.rex"
	ghosttyBundle = "com.mitchellh.ghostty"
	codeWorkspace = "code"
)

func focus(what string) error {
	if !slices.Contains([]string{"agent", "tasks", "reviews"}, what) {
		return fmt.Errorf("%q isn't agent, tasks or reviews", what)
	}
	ws, err := appWindows(rexBundle)
	if err != nil {
		return err
	}
	if _, ok := pickWindow(ws); !ok {
		// Rex shows no window, so it may not be running. open fails only
		// when no app has the bundle ID. -g leaves the window where it is,
		// for bringToCode to move.
		if _, err := runIn("", "open", "-g", "-b", rexBundle); err != nil {
			return focusTmux(what)
		}
		if ws, err = appWindows(rexBundle); err != nil {
			return err
		}
	}
	// Capture whether Rex already has focus before bringToCode focuses it, so
	// jumping from another app does not suppress the session Rex shows behind it.
	shown := focusedRex()
	// AeroSpace and Rex answer separately, so Rex switches to what the key
	// asked for while AeroSpace brings its window forward.
	placed := make(chan error, 1)
	go func() { placed <- bringToCode(rexBundle, ws) }()
	err = focusRex(what, shown)
	return errors.Join(err, <-placed)
}

// focusRex goes to the next agent in the Rex app, or opens the Inbox there
// on its Tasks tabs or on Needs you. shown is the session label Rex displayed
// while focused before the jump, or "" when another app had focus.
func focusRex(what, shown string) error {
	var client string
	connect := func() (err error) { client, err = (mux.Rex{}).App(); return err }
	if what == "agent" {
		r := watchedRex(mux.Rex{}, shown)
		var s mux.Snapshot
		var read error
		var wg sync.WaitGroup
		wg.Go(func() { s, read = r.Snapshot() })
		err := waitFor(connect)
		wg.Wait()
		if err != nil {
			return err
		}
		r.Client = client
		return jumpToAgent(r, s, read)
	}
	if err := waitFor(connect); err != nil {
		return err
	}
	// Run from outside Rex, the popup action has no session or pane of its
	// own, so it gets the session the app shows and that session's pane.
	var session, block string
	err := waitFor(func() (err error) {
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

// shownSession is the session Rex's window shows.
func shownSession() (string, error) {
	label, err := shownLabel()
	if err != nil {
		return "", err
	}
	s, err := mux.Rex{}.Snapshot()
	id, ok := s.Session(label)
	if !ok && err == nil {
		err = fmt.Errorf("no session is labeled %q", label)
	}
	return id, err
}

// shownLabel is the label of the session Rex's window shows. Rex reports no
// such thing, but the window's title ends with the session's label.
func shownLabel() (string, error) {
	ws, err := appWindows(rexBundle)
	if err != nil {
		return "", err
	}
	return windowLabel(ws)
}

// windowLabel is the label of the session that ws, Rex's windows, show.
func windowLabel(ws []window) (string, error) {
	w, ok := pickWindow(ws)
	i := strings.LastIndex(w.title, " - ")
	if !ok || i < 0 {
		return "", errors.New("the Rex window doesn't name a session")
	}
	return w.title[i+len(" - "):], nil
}

// focusedRex is the label of the session Rex shows while Rex itself has
// focus, or "" when another app is focused or AeroSpace can't be asked.
func focusedRex() string {
	line, err := runIn("", "aerospace", "list-windows", "--focused", "--format", "%{app-bundle-id}|%{window-title}")
	if err != nil {
		return ""
	}
	return focusedRexLabel(line)
}

// focusedRexLabel parses aerospace's "bundle-id|title" line for the focused
// window and returns the Rex session label when a Rex session window has focus.
func focusedRexLabel(line string) string {
	bundle, title, ok := strings.Cut(strings.TrimSpace(line), "|")
	if !ok || bundle != rexBundle || strings.HasPrefix(title, "Settings") {
		return ""
	}
	i := strings.LastIndex(title, " - ")
	if i < 0 {
		return ""
	}
	return title[i+len(" - "):]
}

// followFocus calls changed whenever Rex gains or loses focus in AeroSpace,
// so switching back to Rex clears seen reports and switching away surfaces
// blocked ones. Switches between other apps trigger nothing.
func followFocus(changed func()) {
	if _, err := exec.LookPath("aerospace"); err != nil {
		return
	}
	prev := focusedRex()
	for {
		cmd := exec.Command("aerospace", "subscribe", "--no-send-initial", "focus-changed")
		out, err := cmd.StdoutPipe()
		if err == nil {
			err = cmd.Start()
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "ws: aerospace subscribe:", err)
			time.Sleep(5 * time.Second)
			continue
		}
		lines := bufio.NewScanner(out)
		for lines.Scan() {
			if cur := focusedRex(); cur != prev {
				prev = cur
				changed()
			}
		}
		_ = cmd.Wait()
		time.Sleep(5 * time.Second)
		if cur := focusedRex(); cur != prev {
			prev = cur
			changed()
		}
	}
}

// watched gives a Rex backend what you're looking at that the server can't
// tell it: the session Rex's window shows while Rex has focus, and the done
// or error records the --watch job saw you looking at as they came in. tmux
// keeps both itself.
func watched(b mux.Backend) mux.Backend {
	r, ok := b.(mux.Rex)
	if !ok {
		return b
	}
	return watchedRex(r, focusedRex())
}

// watchedRex attaches the focused Rex session label and seen records to r.
func watchedRex(r mux.Rex, shown string) mux.Rex {
	r.Shown = shown
	_ = readJSON("seen.json", &r.Seen)
	return r
}

// focusTmux goes to the next agent, or opens the Inbox popup on its Tasks
// tabs or on Needs you, in the tmux client used last, starting Ghostty on
// tmux's main session when no client is attached.
func focusTmux(what string) error {
	client, err := ensureTmuxClient()
	if err != nil {
		return err
	}
	if what == "agent" {
		t := mux.Tmux{Client: client}
		s, err := t.Snapshot()
		return jumpToAgent(t, s, err)
	}
	// Run from outside tmux, the popup would otherwise belong to the session
	// used last, which may not be the one the client shows.
	pane, err := runIn("", "tmux", "display-message", "-c", client, "-p", "#{pane_id}")
	if err != nil {
		return err
	}
	_, err = runIn("", "tmux", "display-popup", "-c", client, "-t", pane, "-d", "#{pane_current_path}", "-h", "80%", "-w", "90%", "-E", "ws pick "+what)
	return err
}

func ensureTmuxClient() (string, error) {
	clients, _ := runIn("", "tmux", "list-clients", "-F", "#{client_activity} #{client_name}")
	if client := newestClient(clients); client != "" {
		ws, err := appWindows(ghosttyBundle)
		if err != nil {
			return "", err
		}
		return client, bringToCode(ghosttyBundle, ws)
	}
	if _, err := runIn("", "aerospace", "workspace", codeWorkspace); err != nil {
		return "", err
	}
	if _, err := runIn("", "open", "-n", "-b", ghosttyBundle, "--args", "-e", "tmux", "new-session", "-A", "-s", "main"); err != nil {
		return "", err
	}
	var client string
	err := waitFor(func() error {
		clients, _ = runIn("", "tmux", "list-clients", "-F", "#{client_activity} #{client_name}")
		if client = newestClient(clients); client == "" {
			return errors.New("tmux didn't start in Ghostty")
		}
		return nil
	})
	return client, err
}

// bringToCode switches to the code workspace and focuses the app's window
// there, moving one onto it when needed or launching the app on it when none
// exists. ws is the app's windows.
func bringToCode(bundle string, ws []window) error {
	w, ok := pickWindow(ws)
	if !ok {
		if _, err := runIn("", "aerospace", "workspace", codeWorkspace); err != nil {
			return err
		}
		_, err := runIn("", "open", "-b", bundle)
		return err
	}
	if w.workspace != codeWorkspace {
		if _, err := runIn("", "aerospace", "move-node-to-workspace", "--window-id", w.id, codeWorkspace); err != nil {
			return err
		}
	}
	if _, err := runIn("", "aerospace", "workspace", codeWorkspace); err != nil {
		return err
	}
	_, err := runIn("", "aerospace", "focus", "--window-id", w.id)
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
	ws = slices.DeleteFunc(slices.Clone(ws), func(w window) bool { return strings.HasPrefix(w.title, "Settings") })
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
