package main

import (
	"slices"
	"testing"

	"workspace/mux"
)

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
