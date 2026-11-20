package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
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
	p := inboxPopup(mux.Detect(func(string) string { return "" }, ""), kitty.Terminal{}, false)
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

// The Inbox lists Reviews' tabs, then the Tasks tabs. ws pick tasks opens it
// on the first Tasks tab, and each tab keeps its own keys: Ctrl-X on a task
// ticks it, and a pull request's keys don't work there.
func TestTheInboxKeepsEachTabsKeys(t *testing.T) {
	oldHome := home
	home, stateDir = t.TempDir(), t.TempDir()
	t.Cleanup(func() { home = oldHome })
	vault := t.TempDir()
	t.Setenv("VAULT_DIR", vault)
	writeNote(t, vault, "notes/daily/2026-11-09.md", "- [ ] call the bank\n")
	if err := writeJSON("inbox.json", inbox{Fetched: now, Items: []item{
		{ID: "pr", Number: 1, Repo: "owner/repo", Title: "a pull request", Yours: true, Updated: now,
			Reasons: []reason{{Kind: commented, Actor: "alice", At: now, Key: "c1"}}},
	}}); err != nil {
		t.Fatal(err)
	}
	b := mux.Detect(func(string) string { return "" }, "")
	p, onTasks := inboxPopup(b, kitty.Terminal{}, false), inboxPopup(b, kitty.Terminal{}, true)
	var names []string
	for _, tab := range p.Tabs {
		names = append(names, tab.Name)
	}
	if got := strings.Join(names[:3], ", "); got != "Needs you, Pull requests, Issues" || len(names) < 4 {
		t.Fatalf("the tabs are %v, want Reviews' three, then the Tasks tabs", names)
	}
	if p.Start != needsYouTab || onTasks.Start != 3 {
		t.Errorf("the Inbox opens on tabs %d and %d, want Needs you and the first Tasks tab", p.Start, onTasks.Start)
	}
	all := len(p.Tabs) - 1
	rows, err := p.Load(all, func([]popup.Row) {})
	if err != nil || len(rows) != 1 {
		t.Fatalf("the last tab loaded %v (%v), want the one task", rows, err)
	}
	for _, key := range []string{"ctrl+g", "ctrl+o"} {
		if _, ok := working(p, key, all, rows[0]); ok {
			t.Errorf("%s works on a task", key)
		}
	}
	// With no row selected, each tab's own Ctrl-T is the one that works.
	if a, _ := working(p, "ctrl+t", all, popup.Row{}); a.Help != "add" {
		t.Errorf("Ctrl-T on a Tasks tab is %q, want add", a.Help)
	}
	ctrlX, _ := working(p, "ctrl+x", all, rows[0])
	ctrlX.Run(rows[0])()
	if got := readNote(t, vault, "notes/daily/2026-11-09.md"); got != "- [x] call the bank\n" {
		t.Errorf("after Ctrl-X on the task, its note is %q, want the box ticked", got)
	}
	needs, _ := p.Load(needsYouTab, func([]popup.Row) {})
	if len(needs) != 1 || needs[0].ID != "pr" {
		t.Errorf("Needs you lists %v, want only the pull request", needs)
	}
}

type showRecorder struct{ recorder }

func (*showRecorder) Show(mux.Place) error { return nil }

// Ctrl-T on a pull request opens a review tab using each configured agent's
// prompt convention: -- for claude and codex, and -i for agy.
func TestReviewAgentPassesPromptForConfiguredAgent(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	oldHome, oldRoot, oldInteractive := home, worktreeRoot, interactive
	home, worktreeRoot, interactive = t.TempDir(), t.TempDir(), false
	t.Cleanup(func() { home, worktreeRoot, interactive = oldHome, oldRoot, oldInteractive })
	repo := filepath.Join(home, "repo")
	if err := os.Mkdir(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"init", "-q", "-b", "feature"},
		{"remote", "add", "origin", "https://github.com/owner/repo.git"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
	} {
		if _, err := git(repo, args...); err != nil {
			t.Fatal(err)
		}
	}
	realRepo, err := filepath.EvalSymlinks(repo)
	if err != nil {
		t.Fatal(err)
	}
	onPath(t, "gh", "echo feature https://github.com/owner/repo/pull/9")
	it := item{Number: 9, Repo: "owner/repo", URL: "https://github.com/owner/repo/pull/9"}
	snap := mux.Snapshot{
		Sessions: []mux.Session{{ID: "session:repo", Label: "repo"}},
		Panes:    []mux.Pane{{Session: "session:repo", Label: "repo", ID: "pane", Tab: "tab:1", Focused: true}},
	}
	for agent, wantFlag := range map[string]string{"claude": "--", "agy": "-i"} {
		withConfig(t, agent, "tab")
		b := &showRecorder{recorder{snapshot: snap}}
		if err := reviewAgent(b, it); err != nil {
			t.Fatalf("%s: %v", agent, err)
		}
		if len(b.tabs) != 1 || len(b.tabs[0]) != 5 || b.tabs[0][0] != "repo" || b.tabs[0][1] != realRepo ||
			b.tabs[0][2] != agent || b.tabs[0][3] != wantFlag || !strings.Contains(b.tabs[0][4], it.URL) {
			t.Errorf("%s opened tabs %q, want [repo %s %s %s <prompt with %s>]", agent, b.tabs, realRepo, agent, wantFlag, it.URL)
		}
	}
}
