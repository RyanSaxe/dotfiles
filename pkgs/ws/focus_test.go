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
		{"no window", nil, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			if w, _ := pickWindow(c.ws); w.id != c.id {
				t.Errorf("pickWindow = %q, want %q", w.id, c.id)
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
