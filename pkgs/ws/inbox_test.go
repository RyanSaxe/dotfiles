package main

import (
	"encoding/json"
	"slices"
	"testing"
	"time"
)

var now = time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)

// node builds an item the way GitHub's GraphQL returns it.
func node(t *testing.T, raw string) ghNode {
	t.Helper()
	var n ghNode
	if err := json.Unmarshal([]byte(raw), &n); err != nil {
		t.Fatal(err)
	}
	return n
}

const (
	me    = `{"login": "ryansaxe", "__typename": "User"}`
	alice = `{"login": "alice", "__typename": "User"}`
	bot   = `{"login": "dependabot", "__typename": "Bot"}`
)

func comment(id, author, at, body string, reacted bool) string {
	b, _ := json.Marshal(body)
	r := "false"
	if reacted {
		r = "true"
	}
	return `{"id": "` + id + `", "createdAt": "` + at + `", "body": ` + string(b) + `, "author": ` + author + `, "reactionGroups": [{"viewerHasReacted": ` + r + `}]}`
}

func TestTheFourReasons(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want []reasonKind
	}{
		{"a reply owed on your pull request", `{"__typename": "PullRequest", "id": "1", "author": ` + me + `,
			"comments": {"nodes": [` + comment("c1", me, "2026-11-01T00:00:00Z", "done", false) + `, ` + comment("c2", alice, "2026-11-02T00:00:00Z", "one more thing", false) + `]}}`,
			[]reasonKind{commented}},
		{"you replied last", `{"__typename": "PullRequest", "id": "2", "author": ` + me + `,
			"comments": {"nodes": [` + comment("c1", alice, "2026-11-01T00:00:00Z", "question", false) + `, ` + comment("c2", me, "2026-11-02T00:00:00Z", "answer", false) + `]}}`,
			nil},
		{"a reaction counts as an answer", `{"__typename": "Issue", "id": "3", "author": ` + me + `,
			"comments": {"nodes": [` + comment("c1", alice, "2026-11-02T00:00:00Z", "fixed?", true) + `]}}`,
			nil},
		{"people talking where you never took part", `{"__typename": "PullRequest", "id": "4", "author": ` + alice + `,
			"comments": {"nodes": [` + comment("c1", alice, "2026-11-02T00:00:00Z", "thoughts?", false) + `]}}`,
			nil},
		{"an @-mention brings you in", `{"__typename": "Issue", "id": "5", "author": ` + alice + `,
			"comments": {"nodes": [` + comment("c1", alice, "2026-11-02T00:00:00Z", "@ryansaxe can you look", false) + `]}}`,
			[]reasonKind{commented}},
		{"bots don't count", `{"__typename": "PullRequest", "id": "6", "author": ` + me + `,
			"comments": {"nodes": [` + comment("c1", bot, "2026-11-02T00:00:00Z", "bump", false) + `]}}`,
			nil},
		{"red checks come first", `{"__typename": "PullRequest", "id": "7", "author": ` + me + `,
			"comments": {"nodes": [` + comment("c1", alice, "2026-11-02T00:00:00Z", "nit", false) + `]},
			"commits": {"nodes": [{"commit": {"oid": "abc", "statusCheckRollup": {"state": "FAILURE",
				"contexts": {"nodes": [{"name": "lint", "conclusion": "FAILURE"}, {"name": "test", "conclusion": "SUCCESS"}]}}}}]}}`,
			[]reasonKind{failing, commented}},
		{"changes requested on yours", `{"__typename": "PullRequest", "id": "8", "author": ` + me + `,
			"reviews": {"nodes": [{"id": "r1", "state": "CHANGES_REQUESTED", "submittedAt": "2026-11-02T00:00:00Z", "author": ` + alice + `}]}}`,
			[]reasonKind{changesRequested}},
		{"a dismissed review doesn't", `{"__typename": "PullRequest", "id": "9", "author": ` + me + `,
			"reviews": {"nodes": [{"id": "r1", "state": "DISMISSED", "submittedAt": "2026-11-02T00:00:00Z", "author": ` + alice + `}]}}`,
			nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var got []reasonKind
			for _, r := range reasonsFor(node(t, c.raw), "ryansaxe", false, now) {
				got = append(got, r.Kind)
			}
			if !slices.Equal(got, c.want) {
				t.Errorf("reasons %v, want %v", got, c.want)
			}
		})
	}
}

func TestAcknowledgingLastsUntilSomethingNew(t *testing.T) {
	owed := item{ID: "pr", Reasons: []reason{{Kind: commented, Key: "c2"}}}
	a := acks{}
	if got := a.standing(owed); got != needsYou {
		t.Fatalf("before acknowledging: %v, want needsYou", got)
	}
	a = a.apply(ackEvent{acknowledge: &owed})
	if got := a.standing(owed); got != acknowledged {
		t.Fatalf("after acknowledging: %v, want acknowledged", got)
	}
	newer := item{ID: "pr", Reasons: []reason{{Kind: commented, Key: "c3"}}}
	if got := a.standing(newer); got != needsYou {
		t.Fatalf("after a new comment: %v, want needsYou", got)
	}
	if got := a.standing(item{ID: "pr"}); got != clear {
		t.Fatalf("with no reason left: %v, want clear", got)
	}
	// A fresh inbox without the item drops what you acknowledged, so the same
	// activity on an item that reopens needs you again.
	a = a.apply(ackEvent{fresh: &inbox{}})
	if got := a.standing(owed); got != needsYou {
		t.Fatalf("after the item closed and came back: %v, want needsYou", got)
	}
}

func TestAWatchedRepositorysNewItemNotifies(t *testing.T) {
	cases := []struct {
		name, raw string
		watched   bool
		want      []reasonKind
	}{
		{"new this week", `{"__typename": "PullRequest", "id": "10", "author": ` + alice + `, "createdAt": "2026-11-07T00:00:00Z"}`, true, []reasonKind{opened}},
		{"a draft waits", `{"__typename": "PullRequest", "id": "11", "author": ` + alice + `, "createdAt": "2026-11-07T00:00:00Z", "isDraft": true}`, true, nil},
		{"last month's is old", `{"__typename": "Issue", "id": "12", "author": ` + alice + `, "createdAt": "2026-10-01T00:00:00Z"}`, true, nil},
		{"an unwatched repository's doesn't", `{"__typename": "Issue", "id": "13", "author": ` + alice + `, "createdAt": "2026-11-07T00:00:00Z"}`, false, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var got []reasonKind
			for _, r := range reasonsFor(node(t, c.raw), "ryansaxe", c.watched, now) {
				got = append(got, r.Kind)
			}
			if !slices.Equal(got, c.want) {
				t.Errorf("reasons %v, want %v", got, c.want)
			}
		})
	}
}
