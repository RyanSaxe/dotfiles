package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"workspace/mux"
	"workspace/popup"
)

// gitLog leaves the log that git writes in gitDir when HEAD moves, dated at.
func gitLog(t *testing.T, gitDir string, at time.Time) {
	t.Helper()
	log := filepath.Join(gitDir, "logs", "HEAD")
	if err := os.MkdirAll(filepath.Dir(log), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(log, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(log, at, at); err != nil {
		t.Fatal(err)
	}
}

// Folders lists repositories, worktrees and bookmarks once each, the latest
// git activity first, and Enter on one that is open goes to its place.
// Sessions lists only the places: each session, and each tab named after a
// folder, whichever session it is in.
func TestTheGoPopupsFoldersAndSessions(t *testing.T) {
	scratch := t.TempDir()
	oldHome, oldRoot, oldConfig := home, worktreeRoot, configDir
	home, worktreeRoot, configDir = scratch, filepath.Join(scratch, "worktrees"), filepath.Join(scratch, ".config", "ws")
	t.Cleanup(func() { home, worktreeRoot, configDir = oldHome, oldRoot, oldConfig })

	day := func(d int) time.Time { return time.Date(2026, 11, d, 12, 0, 0, 0, time.UTC) }
	gitLog(t, filepath.Join(scratch, "Projects", "quiet", ".git"), day(1))
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
list-panes) printf 'busy\t11\t%%1\t\tzsh\t/elsewhere\t0\t0\t@1\t\tbusy\nbusy\t01\t%%3\t\tzsh\t/elsewhere\t0\t0\t@3\tquiet/feature\tfeature\nbusy\t01\t%%4\t\tnvim\t/elsewhere\t0\t0\t@4\tquiet/feature\tREADME\nscratch\t11\t%%2\t\tzsh\t/elsewhere\t0\t0\t@2\t\tscratch\n';;
esac`)
	p := goPopup(mux.Detect(func(k string) string { return map[string]string{"TMUX": "/tmp/tmux-501/default,1,0"}[k] }, ""), foldersTab)

	var early []popup.Row // the rows Folders shows before the snapshot
	folders, err := p.Load(foldersTab, func(rows []popup.Row) { early = rows })
	if err != nil {
		t.Fatal(err)
	}
	var titles []string
	for _, r := range folders {
		titles = append(titles, r.Title)
	}
	if want := []string{"quiet/feature", "busy", "quiet", "notes"}; !slices.Equal(titles, want) {
		t.Errorf("Folders lists %v, want %v", titles, want)
	}
	var tags []string
	for _, r := range folders {
		tags = append(tags, r.Tag.String())
	}
	if want := []string{"tab", "session", "bookmark", "bookmark"}; !slices.Equal(tags, want) {
		t.Errorf("Folders tags its rows %q, want %q", tags, want)
	}
	enter := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "enter" })]
	if msg := enter.Run(folders[1])(); msg != popup.Quit {
		t.Errorf("Enter on busy gave %v, want the popup to close", msg)
	}
	if got := readNote(t, filepath.Dir(calls), "calls"); !strings.Contains(got, "switch-client -t @1\n") {
		t.Errorf("Enter on busy, which has a session, ran tmux with\n%s", got)
	}
	// Ctrl-X asks before it closes a place, and only y closes it. A row shown
	// before the snapshot doesn't know its place, so Ctrl-X closes it only
	// once the snapshot comes.
	ctrlX := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "ctrl+x" })]
	i := slices.IndexFunc(early, func(r popup.Row) bool { return r.Title == "busy" })
	if i < 0 || early[i].Tag.String() == "session" {
		t.Fatalf("Folders showed %v before the snapshot", early)
	}
	if ctrlX.When(foldersTab, early[i]) {
		t.Error("Ctrl-X offers to close busy before the snapshot says it has a session")
	}
	if !ctrlX.When(foldersTab, folders[0]) || !ctrlX.When(foldersTab, folders[1]) || ctrlX.When(foldersTab, folders[2]) {
		t.Error("Ctrl-X isn't offered on exactly the folders that are open")
	}
	closeRow := func(row int, answer string) string {
		m, _ := popup.New(p, nil).Update(ctrlX.Run(folders[row])())
		m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(answer)})
		if _, then := m.Update(tea.KeyMsg{Type: tea.KeyEnter}); then != nil {
			then()
		}
		return readNote(t, filepath.Dir(calls), "calls")
	}
	if got := closeRow(1, "n"); strings.Contains(got, "kill-") {
		t.Errorf("Ctrl-X on busy, answered n, ran tmux with\n%s", got)
	}
	// busy's session holds quiet/feature's two tabs too, so closing busy
	// closes only its own tab, and closing quiet/feature closes its two in one
	// command, which tmux finishes even when ws runs in the first.
	if got := closeRow(1, "y"); !strings.Contains(got, "kill-window -t @1\n") || strings.Contains(got, "kill-session") {
		t.Errorf("Ctrl-X on busy, answered y, ran tmux with\n%s", got)
	}
	if got := closeRow(0, "y"); !strings.Contains(got, "kill-window -t @3 ; kill-window -t @4\n") || strings.Contains(got, "kill-session") {
		t.Errorf("Ctrl-X on quiet/feature, answered y, ran tmux with\n%s", got)
	}

	sessions, err := p.Load(sessionsTab, func([]popup.Row) {})
	if err != nil {
		t.Fatal(err)
	}
	var listed []string
	for _, r := range sessions {
		listed = append(listed, r.Title+" in "+r.Detail)
	}
	if want := []string{"busy in ~/Projects/busy", "quiet/feature in ~/worktrees/quiet/feature", "scratch in /elsewhere"}; !slices.Equal(listed, want) {
		t.Errorf("Sessions lists %v, want %v", listed, want)
	}
	// scratch is a session with nothing else in it, so closing it closes the
	// session.
	m, _ := popup.New(p, nil).Update(ctrlX.Run(sessions[2])())
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	if _, then := m.Update(tea.KeyMsg{Type: tea.KeyEnter}); then != nil {
		then()
	}
	if got := readNote(t, filepath.Dir(calls), "calls"); !strings.Contains(got, "kill-session -t =scratch\n") {
		t.Errorf("Ctrl-X on scratch, answered y, ran tmux with\n%s", got)
	}
}

// The preview lists a repository's top folder even when it holds more than
// the 25 entries tree opens a folder for.
func TestTheFolderPreviewListsALargeTopFolder(t *testing.T) {
	for _, tool := range []string{"git", "tree"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool + " is not installed")
		}
	}
	// A commit hook runs these tests, and the scratch repository must not be
	// the one being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	dir := t.TempDir()
	if out, err := exec.Command("git", "-C", dir, "init", "-q").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v %s", err, out)
	}
	writeNote(t, dir, "src/main.go", "package main")
	for i := range 30 {
		writeNote(t, dir, fmt.Sprintf("note%02d.md", i), "")
	}
	// Committed, so git status doesn't list the files itself.
	for _, args := range [][]string{{"add", "."}, {"-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "files"}} {
		if out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
	}

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
		{foldersTab, place{dir: "/p", at: mux.Place{Session: "s"}}, []string{"enter", "ctrl+x", "ctrl+f"}},
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
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	// A commit hook runs these tests, and ws must not reach the repository
	// being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	stateDir = t.TempDir()
	withConfig(t, "claude", "tab")
	projects := t.TempDir()
	for _, name := range []string{"mine", "other"} {
		if err := os.Mkdir(filepath.Join(projects, name), 0o755); err != nil {
			t.Fatal(err)
		}
		for _, args := range [][]string{
			{"init", "-q", "-b", "main"},
			{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
		} {
			if _, err := git(filepath.Join(projects, name), args...); err != nil {
				t.Fatal(err)
			}
		}
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
	m, msg := popup.New(p, nil), ctrlT.Run(rows[0])()
	for _, answer := range []string{"fix", "", ""} { // its name, the default agent and no prompt
		m, _ = m.Update(msg)
		m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(answer)})
		_, then := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
		msg = then()
	}
	for _, cmd := range msg.(tea.BatchMsg) {
		cmd()
	}
	if _, err := os.Stat(filepath.Join(worktreeRoot, "mine", "fix")); err != nil {
		t.Errorf("Ctrl-T didn't make mine/fix: %v", err)
	}
	if _, err := os.Stat(filepath.Join(worktreeRoot, "other", "fix")); err == nil {
		t.Error("Ctrl-T made other/fix, in the selected row's project")
	}
}
