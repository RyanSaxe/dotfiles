package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
	"workspace/mux"
	"workspace/popup"

	tea "github.com/charmbracelet/bubbletea"
)

// gitLog leaves the log that git writes in gitDir when HEAD moves, dated at.
func gitLog(t *testing.T, gitDir string, at time.Time) {
	t.Helper()
	log := filepath.Join(gitDir, "logs", "HEAD")
	if err := os.MkdirAll(filepath.Dir(log), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(log, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(log, at, at); err != nil {
		t.Fatal(err)
	}
}

func rowTitles(rows []popup.Row) []string {
	titles := make([]string, len(rows))
	for i, r := range rows {
		titles[i] = r.Title
	}
	return titles
}

func rowTags(rows []popup.Row) []string {
	tags := make([]string, len(rows))
	for i, r := range rows {
		tags[i] = r.Tag.String()
	}
	return tags
}

type goPopupHarness struct {
	p     popup.Popup
	ctrlX popup.Action
	calls string
}

func (h goPopupHarness) confirmClose(t *testing.T, row popup.Row, answer string) string {
	t.Helper()
	m, _ := popup.New(h.p, nil).Update(h.ctrlX.Run(row)())
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(answer)})
	if _, then := m.Update(tea.KeyMsg{Type: tea.KeyEnter}); then != nil {
		then()
	}
	return readNote(t, filepath.Dir(h.calls), "calls")
}

func setupGoPopupFixture(t *testing.T) goPopupHarness {
	t.Helper()
	scratch := t.TempDir()
	oldHome, oldRoot, oldConfig := home, worktreeRoot, configDir
	home, worktreeRoot, configDir = scratch, filepath.Join(scratch, "worktrees"), filepath.Join(scratch, ".config", "ws")
	t.Cleanup(func() { home, worktreeRoot, configDir = oldHome, oldRoot, oldConfig })

	day := func(d int) time.Time { return time.Date(2026, 11, d, 12, 0, 0, 0, time.UTC) }
	gitLog(t, filepath.Join(scratch, "Projects", "quiet", ".git"), day(1))
	gitLog(t, filepath.Join(scratch, "Projects", "Games", "busy", ".git"), day(5))
	gitLog(t, filepath.Join(scratch, "Projects", "busy", ".git"), day(8))
	// A worktree's .git is a file naming its folder in the main checkout.
	feature := filepath.Join(worktreeRoot, "quiet", "feature")
	writeNote(t, feature, ".git", "gitdir: "+filepath.Join(scratch, "Projects", "quiet", ".git", "worktrees", "feature")+"\n")
	gitLog(t, filepath.Join(scratch, "Projects", "quiet", ".git", "worktrees", "feature"), day(10))
	writeNote(t, scratch, "notes/inbox.md", "")
	writeNote(t, scratch, ".config/ws/bookmarks", "~/notes\n~/Projects/quiet\n")

	calls := filepath.Join(t.TempDir(), "calls")
	onPath(t, "tmux", `echo "$*" >> `+calls+`
case "$2" in
list-panes) printf 'Projects/busy\t11\t%%1\t\tzsh\t/elsewhere\t0\t0\t@1\t\tbusy\nProjects/busy\t01\t%%3\t\tzsh\t/elsewhere\t0\t0\t@3\tquiet/feature\tfeature\nProjects/busy\t01\t%%4\t\tnvim\t/elsewhere\t0\t0\t@4\tquiet/feature\tREADME\nscratch\t11\t%%2\t\tzsh\t/elsewhere\t0\t0\t@2\t\tscratch\n';;
esac`)
	p := goPopup(mux.Detect(func(k string) string { return map[string]string{"TMUX": "/tmp/tmux-501/default,1,0"}[k] }, ""), foldersTab)
	ctrlX := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "ctrl+x" })]
	return goPopupHarness{p: p, ctrlX: ctrlX, calls: calls}
}

func checkFoldersTab(t *testing.T, h goPopupHarness) {
	t.Helper()
	var first, early []popup.Row // the rows Folders shows first, and last before the snapshot
	folders, err := h.p.Load(foldersTab, func(rows []popup.Row) {
		if first == nil {
			first = rows
		}
		early = rows
	})
	if err != nil {
		t.Fatal(err)
	}
	// The worktrees and bookmarks show before the walk finds busy.
	if got, want := rowTitles(first), []string{"quiet/feature", "quiet", "notes"}; !slices.Equal(got, want) {
		t.Errorf("Folders first shows %q, want %q", got, want)
	}
	if titles, want := rowTitles(folders), []string{"quiet/feature", "busy", "busy", "quiet", "notes"}; !slices.Equal(titles, want) {
		t.Errorf("Folders lists %v, want %v", titles, want)
	}
	if tags, want := rowTags(folders), []string{"tab", "session", "", "bookmark", "bookmark"}; !slices.Equal(tags, want) {
		t.Errorf("Folders tags its rows %q, want %q", tags, want)
	}
	enter := h.p.Actions[slices.IndexFunc(h.p.Actions, func(a popup.Action) bool { return a.Key == "enter" })]
	if msg := enter.Run(folders[1])(); msg != popup.Quit {
		t.Errorf("Enter on busy gave %v, want the popup to close", msg)
	}
	if got := readNote(t, filepath.Dir(h.calls), "calls"); !strings.Contains(got, "switch-client -t @1\n") {
		t.Errorf("Enter on busy, which has a session, ran tmux with\n%s", got)
	}
	checkFoldersCtrlX(t, h, early, folders)
}

func checkFoldersCtrlX(t *testing.T, h goPopupHarness, early, folders []popup.Row) {
	t.Helper()
	checkFoldersCtrlXAvailability(t, h, early, folders)
	if got := h.confirmClose(t, folders[1], "n"); strings.Contains(got, "kill-") {
		t.Errorf("Ctrl-X on busy, answered n, ran tmux with\n%s", got)
	}
	// busy's session holds quiet/feature's two tabs too, so closing busy
	// closes only its own tab, and closing quiet/feature closes its two in one
	// command, which tmux finishes even when ws runs in the first.
	if got := h.confirmClose(t, folders[1], "y"); !strings.Contains(got, "kill-window -t @1\n") || strings.Contains(got, "kill-session") {
		t.Errorf("Ctrl-X on busy, answered y, ran tmux with\n%s", got)
	}
	if got := h.confirmClose(t, folders[0], "y"); !strings.Contains(got, "kill-window -t @3 ; kill-window -t @4\n") || strings.Contains(got, "kill-session") {
		t.Errorf("Ctrl-X on quiet/feature, answered y, ran tmux with\n%s", got)
	}
}

func checkFoldersCtrlXAvailability(t *testing.T, h goPopupHarness, early, folders []popup.Row) {
	t.Helper()
	// Ctrl-X asks before it closes a place, and only y closes it. A row shown
	// before the snapshot doesn't know its place, so Ctrl-X closes it only
	// once the snapshot comes.
	i := slices.IndexFunc(early, func(r popup.Row) bool { return r.Title == "busy" })
	if i < 0 || early[i].Tag.String() == "session" {
		t.Fatalf("Folders showed %v before the snapshot", early)
	}
	if h.ctrlX.When(foldersTab, early[i]) {
		t.Error("Ctrl-X offers to close busy before the snapshot says it has a session")
	}
	if !h.ctrlX.When(foldersTab, folders[0]) || !h.ctrlX.When(foldersTab, folders[1]) || h.ctrlX.When(foldersTab, folders[2]) || h.ctrlX.When(foldersTab, folders[3]) {
		t.Error("Ctrl-X isn't offered on exactly the folders that are open")
	}
}

func checkSessionsTab(t *testing.T, h goPopupHarness) {
	t.Helper()
	sessions, err := h.p.Load(sessionsTab, func([]popup.Row) {})
	if err != nil {
		t.Fatal(err)
	}
	var listed []string
	for _, r := range sessions {
		listed = append(listed, r.Title+" in "+r.Detail)
	}
	if want := []string{"Projects/busy in ~/Projects/busy", "quiet/feature in ~/worktrees/quiet/feature", "scratch in /elsewhere"}; !slices.Equal(listed, want) {
		t.Errorf("Sessions lists %v, want %v", listed, want)
	}
	// scratch is a session with nothing else in it, so closing it closes the
	// session.
	if got := h.confirmClose(t, sessions[2], "y"); !strings.Contains(got, "kill-session -t =scratch\n") {
		t.Errorf("Ctrl-X on scratch, answered y, ran tmux with\n%s", got)
	}
}

// Folders lists repositories, worktrees and bookmarks once each, the latest
// git activity first, and Enter on one that is open goes to its place.
// Sessions lists only the places: each session, and each tab named after a
// folder, whichever session it is in.
func TestTheGoPopupsFoldersAndSessions(t *testing.T) {
	h := setupGoPopupFixture(t)
	checkFoldersTab(t, h)
	checkSessionsTab(t, h)
}

// The preview lists a repository's top folder even when it holds more than
// the 25 entries tree opens a folder for.
func TestTheFolderPreviewListsALargeTopFolder(t *testing.T) {
	requireTools(t, "git", "tree")
	clearGitHookEnv(t)
	dir := t.TempDir()
	if _, err := git(dir, "init", "-q"); err != nil {
		t.Fatalf("git init: %v", err)
	}
	writeNote(t, dir, "src/main.go", "package main")
	for i := range 30 {
		writeNote(t, dir, fmt.Sprintf("note%02d.md", i), "")
	}
	// Committed, so git status doesn't list the files itself.
	runGitSteps(t, dir, []string{"add", "."}, []string{"-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "files"})

	preview, err := goPopup(nil, foldersTab).Fetch(popup.Row{Data: place{dir: dir}})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"src", "note00.md", "note29.md"} {
		if !strings.Contains(preview.(string), want) {
			t.Errorf("the preview leaves out %s:\n%s", want, preview)
		}
	}
}

// A session with no pane to land on, such as one Rex is still making, reads
// as open, and its preview captures no pane.
func TestASessionWithNoPaneToLandOnReadsAsOpen(t *testing.T) {
	rows := sessionRows(nil, mux.Snapshot{Sessions: []mux.Session{{ID: "s", Label: "new"}}})
	if tag := rows[0].Tag.String(); tag != "open" {
		t.Errorf("the session is tagged %q, want open", tag)
	}
	if preview, err := goPopup(nil, sessionsTab).Fetch(rows[0]); preview != nil || err != nil {
		t.Errorf("the preview is %v (%v), want none", preview, err)
	}
}

// Each tab of the go popup offers its own keys, in the order every popup
// lists them, and no other tab's.
func TestEachGoTabOffersItsOwnKeys(t *testing.T) {
	p := goPopup(nil, foldersTab)
	for _, tc := range []struct {
		tab  int
		row  any
		want []string
	}{
		{foldersTab, place{dir: "/p", at: mux.Place{Session: "s"}}, []string{"enter", "ctrl+t", "ctrl+x", "ctrl+f"}},
		{worktreesTab, worktreeRow{base: "origin/main", pr: "https://github.com/o/r/pull/1"}, []string{"enter", "ctrl+t", "ctrl+x", "ctrl+f", "ctrl+g", "ctrl+o"}},
		{sessionsTab, place{dir: "/p", at: mux.Place{Session: "s"}}, []string{"enter", "ctrl+x", "ctrl+f"}},
		{agentsTab, mux.Pane{ID: "%1"}, []string{"enter"}},
	} {
		var keys []string
		for _, a := range p.Actions {
			if a.When == nil || a.When(tc.tab, popup.Row{Data: tc.row}) {
				keys = append(keys, a.Key)
			}
		}
		if !slices.Equal(keys, tc.want) {
			t.Errorf("%s offers %v, want %v", p.Tabs[tc.tab].Name, keys, tc.want)
		}
	}
}

// Ctrl-T on Worktrees makes the worktree in the project ws runs in, even
// when that project has none yet and another project's row is selected.
func TestCtrlTMakesAWorktreeOfTheProjectWsRunsIn(t *testing.T) {
	requireTools(t, "git")
	clearGitHookEnv(t)
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	stateDir = t.TempDir()
	withConfig(t, "claude", "tab")
	projects := t.TempDir()
	for _, name := range []string{"mine", "other"} {
		dir := filepath.Join(projects, name)
		if err := os.Mkdir(dir, 0o750); err != nil {
			t.Fatal(err)
		}
		initBaseRepo(t, dir)
	}
	if _, err := git(filepath.Join(projects, "other"), "worktree", "add", "-q", "-b", "feat", filepath.Join(worktreeRoot, "other", "feat")); err != nil {
		t.Fatal(err)
	}
	t.Chdir(filepath.Join(projects, "mine"))
	onPath(t, "tmux", "exit 0") // a tmux server with no sessions

	p := goPopup(mux.Detect(func(string) string { return "" }, ""), worktreesTab)
	rows, err := p.Load(worktreesTab, func([]popup.Row) {})
	if err != nil || len(rows) != 1 {
		t.Fatalf("Worktrees lists %v (%v), want other's feat", rows, err)
	}
	ctrlT, _ := working(p, "ctrl+t", worktreesTab, rows[0])
	answerPrompts(p, ctrlT.Run(rows[0])(), "fix", "", "") // its name, the default agent and no prompt
	if _, err := os.Stat(filepath.Join(worktreeRoot, "mine", "fix")); err != nil {
		t.Errorf("Ctrl-T didn't make mine/fix: %v", err)
	}
	if _, err := os.Stat(filepath.Join(worktreeRoot, "other", "fix")); err == nil {
		t.Error("Ctrl-T made other/fix, in the selected row's project")
	}
}

func answerPrompts(p popup.Popup, msg tea.Msg, answers ...string) {
	m := popup.New(p, nil)
	for _, answer := range answers {
		m, _ = m.Update(msg)
		m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(answer)})
		_, then := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
		msg = then()
	}
	for _, cmd := range msg.(tea.BatchMsg) {
		cmd()
	}
}
