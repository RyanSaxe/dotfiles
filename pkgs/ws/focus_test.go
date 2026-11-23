package main

import "testing"

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
