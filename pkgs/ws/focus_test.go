package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPickWindow(t *testing.T) {
	for _, c := range []struct {
		name string
		ws   []window
		id   string
	}{
		{"one on code wins", []window{{"11", "browser", "Rex"}, {"12", "code", "Rex"}}, "12"},
		{"else the first, to move", []window{{"11", "browser", "Rex"}, {"12", "message", "Rex"}}, "11"},
		{"never Settings", []window{{"10", "code", "Settings - Interface"}, {"11", "browser", "Rex"}}, "11"},
		{"only Settings", []window{{"10", "code", "Settings - Interface"}}, ""},
		{"no window", nil, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			// ws focus picks from one list more than once.
			for range 2 {
				if w, ok := pickWindow(c.ws); w.id != c.id || ok != (c.id != "") {
					t.Fatalf("pickWindow = %q, %v, want %q", w.id, ok, c.id)
				}
			}
		})
	}
}

func TestNewestClient(t *testing.T) {
	if got := newestClient("1700000000 /dev/ttys001\n1700000500 /dev/ttys004\n1700000200 /dev/ttys002"); got != "/dev/ttys004" {
		t.Errorf("newestClient = %q, want the most recently active", got)
	}
	if got := newestClient(""); got != "" {
		t.Errorf("newestClient with no clients = %q, want none", got)
	}
}

func TestFocusedRexLabel(t *testing.T) {
	for _, c := range []struct {
		name string
		line string
		want string
	}{
		{"focused Rex session", "com.superlogical.rex|zsh - dotfiles\n", "dotfiles"},
		{"title with multiple dashes", "com.superlogical.rex|a - b - dotfiles", "dotfiles"},
		{"Rex Settings window", "com.superlogical.rex|Settings - Interface", ""},
		{"Rex window without session", "com.superlogical.rex|Rex", ""},
		{"browser focused while title looks like a session", "com.google.Chrome|PR #230 - dotfiles", ""},
		{"empty output", "", ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			if got := focusedRexLabel(c.line); got != c.want {
				t.Errorf("focusedRexLabel(%q) = %q, want %q", c.line, got, c.want)
			}
		})
	}
}

func TestFocusAgentFromAnotherAppJumpsToUnfocusedRexSession(t *testing.T) {
	stateDir = t.TempDir()
	bin := t.TempDir()
	focusLog := filepath.Join(bin, "focus.log")
	aeroLog := filepath.Join(bin, "aero.log")
	aerospace := `#!/bin/sh
echo "$*" >> "` + aeroLog + `"
case "$*" in
  *"--focused"*) echo "com.google.Chrome|Docs - Google Chrome" ;;
  *"--app-bundle-id com.superlogical.rex"*) echo "101|code|agy - frontend" ;;
  *) exit 0 ;;
esac
`
	rex := `#!/bin/sh
case "$*" in
  *"client ls"*) echo '{"clients":[{"client_id":"c1","connection_state":"connected","info":{"kind":"app","platform":"macos"}}]}' ;;
  *"session_id="*) echo "$*" >> "` + focusLog + `" ;;
  *"do -"*)
    cat >/dev/null
    cat <<'EOF'
{"sessions":[{"id":"s1","label":"frontend"}],
 "panes":[
  {"session":"s1","label":"frontend","id":"p1","tab":"w1","focused":true,"landing":true,"visible":true,"status":"error","updated":"2026-11-25T12:05:00Z","shown":["2026-11-25T12:00:00Z"]},
  {"session":"s1","label":"frontend","id":"p3","tab":"w2","tab_name":"frontend/fix","focused":true,"landing":false,"visible":false,"status":"done","updated":"2026-11-25T12:05:00Z","shown":["2026-11-25T12:00:00Z"]}
 ]}
EOF
    ;;
esac
`
	for name, body := range map[string]string{"aerospace": aerospace, "rex": rex} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o700); err != nil { //nolint:gosec // test writes executable shims to temp PATH
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))

	if err := focus("agent"); err != nil {
		t.Fatalf("focus(agent) failed: %v", err)
	}
	got, err := os.ReadFile(focusLog) //nolint:gosec // reads test log in t.TempDir()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "block_id=p1") {
		t.Errorf("focus(agent) from browser jumped to %q, want failed pane p1", strings.TrimSpace(string(got)))
	}
	aero, err := os.ReadFile(aeroLog) //nolint:gosec // reads test log in t.TempDir()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(aero), "workspace code") {
		t.Errorf("focus(agent) did not switch to code workspace; aerospace calls:\n%s", aero)
	}
}
