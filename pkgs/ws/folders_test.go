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
// git activity first, and Enter on one with a session goes to that session.
// Sessions lists only the running sessions.
func TestTheGoPopupsFoldersAndSessions(t *testing.T) {
	scratch := t.TempDir()
	oldHome, oldRoot := home, worktreeRoot
	home, worktreeRoot = scratch, filepath.Join(scratch, "worktrees")
	t.Cleanup(func() { home, worktreeRoot = oldHome, oldRoot })

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
list-panes) printf 'busy\t11\t%%1\t\tzsh\t/elsewhere\tbusy\nscratch\t11\t%%2\t\tzsh\t/elsewhere\tscratch\n';;
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
	if want := []string{"", "session", "bookmark", "bookmark"}; !slices.Equal(tags, want) {
		t.Errorf("Folders tags its rows %q, want %q", tags, want)
	}
	enter := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "enter" })]
	if msg := enter.Run(folders[1])(); msg != popup.Quit {
		t.Errorf("Enter on busy gave %v, want the popup to close", msg)
	}
	if got := readNote(t, filepath.Dir(calls), "calls"); !strings.Contains(got, "switch-client -t =busy\n") {
		t.Errorf("Enter on busy, which has a session, ran tmux with\n%s", got)
	}
	// A row shown before the snapshot doesn't know its session, and its
	// actions still find it.
	ctrlX := p.Actions[slices.IndexFunc(p.Actions, func(a popup.Action) bool { return a.Key == "ctrl+x" })]
	i := slices.IndexFunc(early, func(r popup.Row) bool { return r.Title == "busy" })
	if i < 0 || early[i].Tag.String() == "session" {
		t.Fatalf("Folders showed %v before the snapshot", early)
	}
	ctrlX.Run(early[i])()
	if got := readNote(t, filepath.Dir(calls), "calls"); !strings.Contains(got, "kill-session -t =busy\n") {
		t.Errorf("Ctrl-X on busy as it showed before the snapshot ran tmux with\n%s", got)
	}

	sessions, err := p.Load(sessionsTab, func([]popup.Row) {})
	if err != nil {
		t.Fatal(err)
	}
	var listed []string
	for _, r := range sessions {
		listed = append(listed, r.Title+" in "+r.Detail)
	}
	if want := []string{"busy in ~/Projects/busy", "scratch in /elsewhere"}; !slices.Equal(listed, want) {
		t.Errorf("Sessions lists %v, want %v", listed, want)
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
