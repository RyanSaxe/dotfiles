package main

import (
	"slices"
	"testing"

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

func TestNextAgent(t *testing.T) {
	agents := []mux.Terminal{
		{Label: "web", Block: "idle", Status: mux.Idle},
		{Label: "api", Block: "done-b", Status: mux.Done},
		{Label: "shell", Block: "plain", Status: mux.Open},
		{Label: "api", Block: "working", Status: mux.Working},
		{Label: "app", Block: "done-a", Status: mux.Done},
	}
	blocked := append(slices.Clone(agents), mux.Terminal{Label: "zeta", Block: "blocked", Status: mux.Blocked})

	cases := []struct {
		name  string
		ts    []mux.Terminal
		last  string
		block string
	}{
		{"a first jump goes to the most urgent", agents, "", "done-b"},
		{"the next jump moves on in order of need", agents, "done-b", "done-a"},
		{"done comes before working", agents, "done-a", "working"},
		{"the last agent wraps to the first", agents, "idle", "done-b"},
		{"a jump whose agent is gone starts over", agents, "closed", "done-b"},
		{"a blocked agent comes first", blocked, "done-b", "blocked"},
		{"after a blocked agent the walk goes on", blocked, "blocked", "done-b"},
	}
	for _, c := range cases {
		got, ok := nextAgent(c.ts, c.last)
		if !ok || got.Block != c.block {
			t.Errorf("%s: went to %q, want %q", c.name, got.Block, c.block)
		}
	}
	if _, ok := nextAgent([]mux.Terminal{{Block: "plain", Status: mux.Open}}, ""); ok {
		t.Error("a jump found an agent where only plain terminals run")
	}
}
