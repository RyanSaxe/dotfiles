package main

import (
	"slices"
	"testing"

	"workspace/kitty"
	"workspace/mux"
	"workspace/popup"
)

// working is the popup's action on key that works on the tab and the row,
// the one the frame lists and runs.
func working(p popup.Popup, key string, tab int, r popup.Row) (popup.Action, bool) {
	for _, a := range p.Actions {
		if a.Key == key && (a.When == nil || a.When(tab, r)) {
			return a, true
		}
	}
	return popup.Action{}, false
}

// Opening an item in Reviews leaves it on Needs you, and only Ctrl-X there
// marks it done. Ctrl-G and Ctrl-T work only on pull requests.
func TestOnlyCtrlXMarksAReviewDone(t *testing.T) {
	oldHome := home
	home, stateDir = t.TempDir(), t.TempDir()
	t.Cleanup(func() { home = oldHome })
	onPath(t, "gh", "exit 0") // Enter on an issue opens it in the browser
	why := []reason{{Kind: commented, Actor: "alice", At: now, Key: "c1"}}
	if err := writeJSON("inbox.json", inbox{Fetched: now, Items: []item{
		{ID: "pr", Number: 1, Repo: "owner/repo", Title: "a pull request", Yours: true, Updated: now, Reasons: why},
		{ID: "issue", Number: 2, Repo: "owner/repo", Title: "an issue", Issue: true, Yours: true, Updated: now, Reasons: why},
	}}); err != nil {
		t.Fatal(err)
	}
	p := reviewsPopup(mux.Detect(func(string) string { return "" }, ""), kitty.Terminal{})
	load := func(tab int) map[string]popup.Row {
		rows, err := p.Load(tab, func([]popup.Row) {})
		if err != nil {
			t.Fatal(err)
		}
		byID := map[string]popup.Row{}
		for _, r := range rows {
			byID[r.ID] = r
		}
		return byID
	}
	needsYou := func() []string {
		ids := []string{}
		for id := range load(needsYouTab) {
			ids = append(ids, id)
		}
		slices.Sort(ids)
		return ids
	}

	rows := load(needsYouTab)
	pr, issue := rows["pr"], rows["issue"]
	for _, key := range []string{"ctrl+g", "ctrl+t"} {
		if _, ok := working(p, key, needsYouTab, pr); !ok {
			t.Errorf("%s doesn't work on a pull request", key)
		}
		if _, ok := working(p, key, needsYouTab, issue); ok {
			t.Errorf("%s works on an issue", key)
		}
	}
	enter, _ := working(p, "enter", needsYouTab, issue)
	if msg := enter.Run(issue)(); msg != popup.Quit {
		t.Fatalf("Enter on the issue gave %v, want the popup to close", msg)
	}
	if got := needsYou(); !slices.Equal(got, []string{"issue", "pr"}) {
		t.Errorf("after Enter on the issue, Needs you lists %v, want both items still", got)
	}
	if _, ok := working(p, "ctrl+x", 1, load(1)["pr"]); ok {
		t.Error("Ctrl-X works on Pull requests, which isn't Needs you")
	}
	ctrlX, _ := working(p, "ctrl+x", needsYouTab, issue)
	ctrlX.Run(issue)()
	if got := needsYou(); !slices.Equal(got, []string{"pr"}) {
		t.Errorf("after Ctrl-X on the issue, Needs you lists %v, want only pr", got)
	}
}
