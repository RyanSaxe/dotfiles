package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"workspace/kitty"
	"workspace/layout"
	"workspace/mux"
	"workspace/popup"
)

// now is Monday 2026-11-09.

func writeNote(t *testing.T, vault, file, content string) {
	t.Helper()
	path := filepath.Join(vault, file)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readNote(t *testing.T, vault, file string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(vault, file))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestATasksStateSectionAndProject(t *testing.T) {
	vault := t.TempDir()
	writeNote(t, vault, "notes/projects/nix/TODO.md", strings.Join([]string{
		"# nix",
		"- [ ] late 📅 2026-11-08",
		"- [ ] now 📅 2026-11-09",
		"  - [ ] week 📅 2026-11-16",
		"- [ ] far 📅 2026-11-17",
		"- [ ] undated",
		"- [ ] impossible 📅 2026-13-40",
		"- [x] finished 📅 2026-11-01",
		"```",
		"- [ ] a sample",
		"## not a section",
		"```",
		"## vault",
		"- [ ] on a branch",
		"",
		"-[ ] not a task",
	}, "\n"))
	writeNote(t, vault, "notes/daily/2026-11-09.md", "- [ ] outside a project\n")
	writeNote(t, vault, "private/notes/projects/secret/TODO.md", "# secret\n- [ ] a private plan\n")
	writeNote(t, vault, ".obsidian/hidden.md", "- [ ] hidden\n")
	writeNote(t, vault, "notes.txt", "- [ ] not markdown\n")

	ts, err := vaultTasks(vault, now)
	if err != nil {
		t.Fatal(err)
	}
	want := []task{
		{Text: "outside a project", State: "none", File: "notes/daily/2026-11-09.md", Line: 1},
		{Text: "late", Due: "2026-11-08", State: "overdue", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 2},
		{Text: "now", Due: "2026-11-09", State: "today", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 3},
		{Text: "week", Due: "2026-11-16", State: "soon", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 4},
		{Text: "far", Due: "2026-11-17", State: "later", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 5},
		{Text: "undated", State: "none", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 6},
		{Text: "impossible 📅 2026-13-40", State: "none", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 7},
		{Text: "finished", Done: true, Due: "2026-11-01", State: "overdue", Project: "nix", Section: "nix", File: "notes/projects/nix/TODO.md", Line: 8},
		{Text: "on a branch", State: "none", Project: "nix", Section: "vault", File: "notes/projects/nix/TODO.md", Line: 14},
		{Text: "a private plan", State: "none", Project: "secret", Section: "secret", File: "private/notes/projects/secret/TODO.md", Line: 2},
	}
	if len(ts) != len(want) {
		t.Fatalf("got %d tasks, want %d: %+v", len(ts), len(want), ts)
	}
	for i := range want {
		if ts[i] != want[i] {
			t.Errorf("task %d is %+v, want %+v", i, ts[i], want[i])
		}
	}
}

// rumdl wraps a long task at 80 columns, under the task's text, and can
// part 📅 from its date.
func TestAWrappedTaskReadsAsOne(t *testing.T) {
	vault := t.TempDir()
	note := strings.Join([]string{
		"# nix",
		"- [ ] Renew the domain before it lapses and tell the team which registrar holds",
		"      it 📅 2026-11-09",
		"- [ ] Renew the domain before it lapses and tell the team which registrar hol 📅",
		"      2026-11-16",
		"  - [ ] a nested task 📅 2026-11-08 that",
		"        wraps",
		"  - a list item",
		"- [ ] a lazy",
		"continuation",
		"",
		"a paragraph 📅 2026-11-08",
		"- [ ] above a quote",
		"  > a quote 📅 2026-11-08",
		"- [ ] above a table",
		"  | a | b 📅 2026-11-08 |",
		"  | - | - |",
		"- [ ] above a heading",
		"## vault",
		"- [ ] above a fence",
		"```",
		"- [ ] a sample",
		"```",
		"a paragraph",
		"- [ ] Check that the headless shell at the same version as the browser honored",
		"      390. width 📅 2026-11-08",
		"- [ ] above a numbered list",
		"1. a step 📅 2026-11-08",
	}, "\n")
	writeNote(t, vault, "notes/projects/nix/TODO.md", note)

	ts, err := vaultTasks(vault, now)
	if err != nil {
		t.Fatal(err)
	}
	in := func(due, state, section string, line int, text string) task {
		return task{Text: text, Due: due, State: state, Project: "nix", Section: section, File: "notes/projects/nix/TODO.md", Line: line}
	}
	want := []task{
		in("2026-11-09", "today", "nix", 2, "Renew the domain before it lapses and tell the team which registrar holds it"),
		in("2026-11-16", "soon", "nix", 4, "Renew the domain before it lapses and tell the team which registrar hol"),
		in("2026-11-08", "overdue", "nix", 6, "a nested task that wraps"),
		in("", "none", "nix", 9, "a lazy continuation"),
		in("", "none", "nix", 13, "above a quote"),
		in("", "none", "nix", 15, "above a table"),
		in("", "none", "nix", 18, "above a heading"),
		in("", "none", "vault", 20, "above a fence"),
		in("2026-11-08", "overdue", "vault", 25, "Check that the headless shell at the same version as the browser honored 390. width"),
		in("", "none", "vault", 27, "above a numbered list"),
	}
	if len(ts) != len(want) {
		t.Fatalf("got %d tasks, want %d: %+v", len(ts), len(want), ts)
	}
	for i := range want {
		if ts[i] != want[i] {
			t.Errorf("task %d is %+v, want %+v", i, ts[i], want[i])
		}
	}

	// Ticking a wrapped task changes the box on its first line.
	if err := tickTask(vault, ts[1], now); err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(note, "\n")
	lines[3] = strings.Replace(lines[3], "[ ]", "[x]", 1)
	if got, want := readNote(t, vault, "notes/projects/nix/TODO.md"), strings.Join(lines, "\n"); got != want {
		t.Errorf("the note is %q, want %q", got, want)
	}
}

func TestEachFormOfADueDate(t *testing.T) {
	for in, want := range map[string]string{
		"": "", "today": "2026-11-09", "tmr": "2026-11-10", "3d": "2026-11-12", "fri": "2026-11-13",
		"Monday": "2026-11-09", "sun": "2026-11-15", "2027-01-02": "2027-01-02",
	} {
		if got, err := dueDate(in, now); err != nil || got != want {
			t.Errorf("%q is %q (%v), want %q", in, got, err, want)
		}
	}
	for _, in := range []string{"fr", "soon", "2026-13-40", "-1d"} {
		if got, err := dueDate(in, now); err == nil {
			t.Errorf("%q is %q, want an error", in, got)
		}
	}
}

func TestATaskIsAddedAboveTheFirstBranch(t *testing.T) {
	for name, c := range map[string]struct{ before, due, after string }{
		"a missing file":    {"", "2026-11-13", "# nix\n\n- [ ] new 📅 2026-11-13\n"},
		"no branches":       {"# nix\n\n- [ ] old\n", "", "# nix\n\n- [ ] old\n- [ ] new\n"},
		"a branch":          {"# nix\n\n- [ ] old\n\n## vault\n\n- [ ] theirs\n", "", "# nix\n\n- [ ] old\n- [ ] new\n\n## vault\n\n- [ ] theirs\n"},
		"a wrapped task":    {"# nix\n\n- [ ] old\n      wraps\n\n## vault\n", "", "# nix\n\n- [ ] old\n      wraps\n- [ ] new\n\n## vault\n"},
		"only a branch":     {"# nix\n\n## vault\n- [ ] theirs\n", "", "# nix\n\n- [ ] new\n\n## vault\n- [ ] theirs\n"},
		"a fenced ## above": {"# nix\n```\n## sample\n```\n## vault\n", "", "# nix\n```\n## sample\n```\n- [ ] new\n## vault\n"},
	} {
		vault := t.TempDir()
		if c.before != "" {
			writeNote(t, vault, "notes/projects/nix/TODO.md", c.before)
		}
		if err := addTask(vault, "nix", "new", c.due); err != nil {
			t.Fatal(err)
		}
		if got := readNote(t, vault, "notes/projects/nix/TODO.md"); got != c.after {
			t.Errorf("%s: the note is %q, want %q", name, got, c.after)
		}
	}
	if err := addTask(t.TempDir(), "", "new", ""); err == nil {
		t.Error("a task with no project was added")
	}
}

// Enter on a task opens its note, at its line, in a new tab of its project's
// place: the checkout whose origin repository has the project's name, and
// the one git moved last when there are two. A task outside a project, or
// one whose project has no checkout, opens in the vault's place, which ws
// makes when there is none.
func TestEnterOnATaskOpensItsProjectsPlace(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	oldHome, oldInteractive := home, interactive
	home, interactive = t.TempDir(), false
	t.Cleanup(func() { home, interactive = oldHome, oldInteractive })
	withConfig(t, "claude", "tab")
	checkout := func(folder string, at time.Time) string {
		dir := filepath.Join(home, folder, "nix")
		log := filepath.Join(dir, ".git", "logs", "HEAD")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		for _, args := range [][]string{{"init", "-q"}, {"remote", "add", "origin", "git@github.com:someone/nix.git"}} {
			if _, err := git(dir, args...); err != nil {
				t.Fatal(err)
			}
		}
		writeNote(t, dir, ".git/logs/HEAD", "")
		if err := os.Chtimes(log, at, at); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	checkout("old", now.Add(-time.Hour))
	latest := checkout("new", now)
	vault := filepath.Join(home, "vault")
	t.Setenv("VAULT_DIR", vault)
	writeNote(t, vault, "notes/projects/nix/TODO.md", "# nix\n- [ ] pin the flake\n")
	writeNote(t, vault, "notes/projects/gone/TODO.md", "- [ ] no checkout here\n")
	writeNote(t, vault, "notes/daily/2026-11-09.md", "- [ ] call the bank\n")

	for id, want := range map[string]string{
		"notes/projects/nix/TODO.md:2":  latest,
		"notes/projects/gone/TODO.md:1": vault,
		"notes/daily/2026-11-09.md:1":   vault,
	} {
		b := &recorder{snapshot: mux.Snapshot{
			Sessions: []mux.Session{{ID: "session:new/nix", Label: "new/nix"}},
			Panes:    []mux.Pane{{Session: "session:new/nix", Label: "new/nix", ID: "pane", Tab: "tab:1", Focused: true}},
		}}
		p := taskTabs(b, kitty.Terminal{})
		rows, err := p.Load(len(p.Tabs)-1, func([]popup.Row) {})
		i := slices.IndexFunc(rows, func(r popup.Row) bool { return r.ID == id })
		if err != nil || i < 0 {
			t.Fatalf("loaded %v (%v), want a task at %s", rows, err, id)
		}
		enter := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "enter" })]
		if msg := enter.Run(rows[i])(); msg != popup.Quit {
			t.Errorf("%s: Enter gave %v, want the popup to close", id, msg)
		}
		file, line, _ := strings.Cut(id, ":")
		edit := []string{"nvim", "+" + line, filepath.Join(vault, file)}
		if want == vault {
			if len(b.tabs) > 0 || len(b.made) != 1 || b.made[0].dir != vault || b.lastPanes()[0].Run != layout.Line(edit) {
				t.Errorf("%s: Enter ran %q and made %v, want a place for the vault running %q", id, b.tabs, b.made, edit)
			}
		} else if len(b.made) > 0 || len(b.tabs) != 1 || !slices.Equal(b.tabs[0], append([]string{"new/nix", want}, edit...)) {
			t.Errorf("%s: Enter ran %q and made %v, want one tab of new/nix in %s running %q", id, b.tabs, b.made, want, edit)
		}
	}
}

func TestTickingATaskChangesOnlyItsBox(t *testing.T) {
	vault := t.TempDir()
	before := "# nix\r\n\n  - [ ] first [ ] 📅 2026-11-09  \n- [ ] second"
	writeNote(t, vault, "notes/projects/nix/TODO.md", before)
	ts, _ := vaultTasks(vault, now)
	if err := tickTask(vault, ts[0], now); err != nil {
		t.Fatal(err)
	}
	if got, want := readNote(t, vault, "notes/projects/nix/TODO.md"), strings.Replace(before, "[ ]", "[x]", 1); got != want {
		t.Errorf("the note is %q, want %q", got, want)
	}
	// The list is stale once the first task is ticked or the note has moved.
	writeNote(t, vault, "notes/projects/nix/TODO.md", "- [ ] another\n"+readNote(t, vault, "notes/projects/nix/TODO.md"))
	for _, stale := range ts {
		if err := tickTask(vault, stale, now); err == nil {
			t.Errorf("%q was ticked from a stale list", stale.Text)
		}
	}
}

func TestTasksWithoutAVaultSaysSo(t *testing.T) {
	t.Setenv("VAULT_DIR", "")
	p := taskTabs(mux.Detect(func(string) string { return "" }, ""), kitty.Terminal{})
	for tab := range p.Tabs {
		if rows, err := p.Load(tab, func([]popup.Row) {}); err == nil || !strings.Contains(err.Error(), "VAULT_DIR") {
			t.Errorf("tab %d loaded %v (%v), want it to say the vault isn't set up", tab, rows, err)
		}
	}
}
