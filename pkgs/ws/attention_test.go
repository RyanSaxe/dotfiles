package main

import (
	"maps"
	"slices"
	"testing"
	"time"

	"workspace/mux"
)

func TestTaskLevel(t *testing.T) {
	late := task{Due: "2026-11-08", State: "overdue"}
	due := task{Due: "2026-11-09", State: "today"}
	next := task{Due: "2026-11-10", State: "soon"}
	later := task{Due: "2026-11-11", State: "soon"}
	for _, c := range []struct {
		name  string
		tasks []task
		want  string
	}{
		{"overdue wins", []task{next, due, late}, "overdue"},
		{"today beats tomorrow", []task{next, due}, "today"},
		{"tomorrow", []task{later, next}, "tomorrow"},
		{"two days out stays quiet", []task{later, {}}, "none"},
		{"done tasks don't count", []task{{Done: true, Due: "2026-11-08", State: "overdue"}}, "none"},
	} {
		t.Run(c.name, func(t *testing.T) {
			if got := taskLevel(c.tasks, now); got != c.want {
				t.Errorf("taskLevel = %q, want %q", got, c.want)
			}
		})
	}
}

func TestTheTaskLetterStaysOffWithoutAVault(t *testing.T) {
	vault := t.TempDir()
	writeNote(t, vault, "notes/daily/2026-11-08.md", "- [ ] call the bank 📅 2026-11-08\n")
	for _, c := range []struct{ name, dir, want string }{
		{"a vault with an overdue task", vault, "overdue"},
		{"no vault", "", "none"},
	} {
		t.Setenv("VAULT_DIR", c.dir)
		if got, err := vaultTaskLevel(now); got != c.want || err != nil {
			t.Errorf("%s: the level is %q (%v), want %q", c.name, got, err, c.want)
		}
	}
}

func TestAgentLevel(t *testing.T) {
	quiet := []mux.Pane{
		{ID: "working", Status: mux.Working},
		{ID: "seen", Status: mux.Done},
		// Rex reports the agent you're looking at as needing nothing.
		{ID: "looking", Status: mux.Blocked},
	}
	unseen := mux.Pane{ID: "unseen", Status: mux.Done, NeedsYou: true}
	blocked := mux.Pane{ID: "blocked", Status: mux.Blocked, NeedsYou: true}
	failed := mux.Pane{ID: "failed", Status: mux.Error, NeedsYou: true}
	bell := mux.Pane{ID: "bell", Status: mux.Idle, NeedsYou: true}
	for _, c := range []struct {
		name  string
		panes []mux.Pane
		want  string
	}{
		{"nothing needs you", quiet, "none"},
		{"a finished agent you haven't looked at", append(slices.Clone(quiet), unseen), "done"},
		{"a blocked agent outranks a finished one", append(slices.Clone(quiet), unseen, blocked), "waiting"},
		{"a failed agent outranks a blocked one", append(slices.Clone(quiet), unseen, blocked, failed), "failed"},
		{"a tmux bell counts as blocked", []mux.Pane{bell}, "waiting"},
	} {
		if got := agentLevel(mux.Snapshot{Panes: c.panes}); got != c.want {
			t.Errorf("%s: the level is %q, want %q", c.name, got, c.want)
		}
	}
}

func TestNextAgent(t *testing.T) {
	agents := []mux.Pane{
		{Label: "web", ID: "idle", Status: mux.Idle},
		{Label: "api", ID: "done-b", Status: mux.Done},
		{Label: "shell", ID: "plain", Status: mux.Open},
		{Label: "api", ID: "working", Status: mux.Working},
		{Label: "app", ID: "done-a", Status: mux.Done},
	}
	at := func(minute int) time.Time { return time.Date(2026, 11, 17, 12, minute, 0, 0, time.UTC) }
	blocked := append(slices.Clone(agents), mux.Pane{Label: "zeta", ID: "blocked", Status: mux.Blocked, NeedsYou: true, Updated: at(5)})
	waiting := append(slices.Clone(blocked),
		mux.Pane{Label: "beta", ID: "unseen", Status: mux.Done, NeedsYou: true, Updated: at(1)},
		mux.Pane{Label: "gamma", ID: "failed", Status: mux.Error, NeedsYou: true, Updated: at(3)},
		mux.Pane{Label: "eta", ID: "blocked-later", Status: mux.Blocked, NeedsYou: true, Updated: at(8)},
	)
	// Rex reports the agent you're looking at, where the last jump went, as
	// needing nothing.
	lookingAtY := []mux.Pane{
		{Label: "a", ID: "x", Status: mux.Blocked, NeedsYou: true, Updated: at(3)},
		{Label: "b", ID: "y", Status: mux.Error, Updated: at(2)},
		{Label: "c", ID: "z", Status: mux.Error, NeedsYou: true, Updated: at(4)},
	}
	// tmux reports an agent whose window printed in the last few seconds as
	// working.
	bells := []mux.Pane{
		{Label: "api", ID: "rang-last", Status: mux.Working, NeedsYou: true, Updated: at(9)},
		{Label: "web", ID: "rang-first", Status: mux.Idle, NeedsYou: true, Updated: at(1)},
	}

	cases := []struct {
		name  string
		panes []mux.Pane
		last  string
		want  string
	}{
		{"a first jump goes to the most urgent", agents, "", "done-b"},
		{"the next jump moves on in order of need", agents, "done-b", "done-a"},
		{"done comes before working", agents, "done-a", "working"},
		{"the last agent wraps to the first", agents, "idle", "done-b"},
		{"a jump whose agent is gone starts over", agents, "closed", "done-b"},
		{"an agent that needs you comes first", blocked, "done-b", "blocked"},
		{"a lone agent that needs you keeps the jumps", blocked, "blocked", "blocked"},
		{"a failed agent comes before agents that needed you earlier", waiting, "", "failed"},
		{"blocked comes after failed", waiting, "failed", "blocked"},
		{"blocked agents go by how long they have needed you", waiting, "blocked", "blocked-later"},
		{"done comes after blocked", waiting, "blocked-later", "unseen"},
		{"the jumps cycle through the agents that need you", waiting, "unseen", "failed"},
		{"a jump goes on from the agent you're looking at", lookingAtY, "y", "z"},
		{"tmux bells go by how long they have needed you", bells, "", "rang-first"},
	}
	for _, c := range cases {
		got, ok := nextAgent(mux.Snapshot{Panes: c.panes}, c.last)
		if !ok || got.ID != c.want {
			t.Errorf("%s: went to %q, want %q", c.name, got.ID, c.want)
		}
	}
	if _, ok := nextAgent(mux.Snapshot{Panes: []mux.Pane{{ID: "plain", Status: mux.Open}}}, ""); ok {
		t.Error("a jump found an agent where only plain terminals run")
	}
}

// The watch job keeps the done record of the pane you were looking at as it
// finished, so it doesn't need you once you look away, and forgets the
// records of panes that have closed.
func TestTheWatchJobKeepsADoneRecordYouLookedAt(t *testing.T) {
	stateDir = t.TempDir()
	finished := time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)
	s := mux.Snapshot{Panes: []mux.Pane{
		{Label: "api", ID: "looked-at", Landing: true, Status: mux.Done, Updated: finished},
		{Label: "api", ID: "beside", Status: mux.Done, Updated: finished},
		{Label: "web", ID: "elsewhere", Landing: true, Status: mux.Done, Updated: finished},
	}}
	noteSeen(s, "api", map[string]time.Time{"closed": finished})
	var seen map[string]time.Time
	if err := readJSON("seen.json", &seen); err != nil {
		t.Fatal(err)
	}
	if want := map[string]time.Time{"looked-at": finished}; !maps.EqualFunc(seen, want, time.Time.Equal) {
		t.Errorf("the job kept %v, want only the record you looked at", seen)
	}
}
