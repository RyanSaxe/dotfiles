package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"workspace/kitty"
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

// Prettier wraps a long task at 80 columns, under the task's text, and can
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

// Enter on a task opens its note in a new tab of the popup's session and
// lands there. Rex's app keeps showing its own tab when the server makes
// another active, so it is sent to the new one, and tmux shows a new window
// unless told not to.
func TestEnterOnATaskLandsInItsTab(t *testing.T) {
	for _, tc := range []struct {
		name, program, script string
		env                   map[string]string
		want                  []string // lines the program was called with, in order
	}{
		{"rex", "rex",
			`case " $* " in *" run "*) echo '{"window_id":"window:task","block_ids":["block:task"]}';; esac`,
			map[string]string{"REX_BLOCK": "block:popup", "REX_SESSION": "session:work"},
			[]string{
				"--autostart=false run -s session:work -c VAULT --json -- nvim +1 notes/daily/2026-11-09.md",
				"--autostart=false -C client:app do session.select session_id=session:work window_id=window:task",
			}},
		{"tmux", "tmux",
			`case "$1" in display-message) echo work;; esac`,
			map[string]string{"TMUX": "/tmp/tmux-501/default,1,0"},
			[]string{
				"display-message -p #{session_name}",
				"new-window -t =work: -c VAULT -- nvim +1 notes/daily/2026-11-09.md",
			}},
	} {
		vault := t.TempDir()
		t.Setenv("VAULT_DIR", vault)
		writeNote(t, vault, "notes/daily/2026-11-09.md", "- [ ] call the bank\n")
		calls := filepath.Join(t.TempDir(), "calls")
		onPath(t, tc.program, `echo "$*" >> `+calls+"\n"+tc.script)
		p := tasksPopup(mux.Detect(func(k string) string { return tc.env[k] }, "client:app"), kitty.Terminal{})
		rows, err := p.Load(len(p.Tabs)-1, func([]popup.Row) {})
		if err != nil || len(rows) != 1 {
			t.Fatalf("%s: loaded %v (%v), want the one task", tc.name, rows, err)
		}
		enter := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "enter" })]
		if msg := enter.Run(rows[0])(); msg != popup.Quit {
			t.Errorf("%s: Enter gave %v, want the popup to close", tc.name, msg)
		}
		got := strings.Split(strings.TrimSpace(readNote(t, filepath.Dir(calls), "calls")), "\n")
		want := slices.Clone(tc.want)
		for i := range want {
			want[i] = strings.ReplaceAll(want[i], "VAULT", vault)
		}
		if !slices.Equal(got, want) {
			t.Errorf("%s ran\n%s\nwant\n%s", tc.program, strings.Join(got, "\n"), strings.Join(want, "\n"))
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
	p := tasksPopup(mux.Detect(func(string) string { return "" }, ""), kitty.Terminal{})
	for tab := range p.Tabs {
		if rows, err := p.Load(tab, func([]popup.Row) {}); err == nil || !strings.Contains(err.Error(), "VAULT_DIR") {
			t.Errorf("tab %d loaded %v (%v), want it to say the vault isn't set up", tab, rows, err)
		}
	}
}
