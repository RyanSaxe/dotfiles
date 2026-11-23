package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/BurntSushi/toml"

	"workspace/mux"
)

// repoAt leaves a checkout in dir whose origin is url, last active at.
func repoAt(t *testing.T, dir, url string, at time.Time) {
	t.Helper()
	writeNote(t, dir, ".git/config", "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = "+url+"\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n")
	gitLog(t, filepath.Join(dir, ".git"), at)
}

// trusted says whether Claude Code's, Codex's and Antigravity's configs
// under home trust dir.
func trusted(t *testing.T, dir string) (claude, codex, agy bool) {
	t.Helper()
	root, err := filepath.EvalSymlinks(dir)
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Projects map[string]struct{ HasTrustDialogAccepted bool }
	}
	if err := json.Unmarshal([]byte(readNote(t, home, ".claude.json")), &c); err != nil {
		t.Fatal(err)
	}
	var x struct {
		Projects map[string]struct {
			TrustLevel string `toml:"trust_level"`
		}
	}
	if _, err := toml.Decode(readNote(t, home, ".codex/config.toml"), &x); err != nil {
		t.Fatal(err)
	}
	var a struct {
		TrustedWorkspaces []string `json:"trustedWorkspaces"`
	}
	if err := json.Unmarshal([]byte(readNote(t, home, ".gemini/antigravity-cli/settings.json")), &a); err != nil {
		t.Fatal(err)
	}
	return c.Projects[root].HasTrustDialogAccepted, x.Projects[root].TrustLevel == "trusted", slices.Contains(a.TrustedWorkspaces, root)
}

// ws project clones a repository where its owner's others are, makes a new
// project with git init, and stops before it makes anything when it can't
// tell where to put one or its folder is taken. It trusts what it made,
// unless it cloned from an owner with nothing here.
func TestWsProjectPutsEachProjectWhereItBelongs(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	t.Setenv("CLAUDE_CONFIG_DIR", "")
	t.Setenv("CODEX_HOME", "")
	t.Setenv("ANTIGRAVITY_APP_DATA_DIR", "")
	oldHome := home
	home = t.TempDir()
	t.Cleanup(func() { home = oldHome })

	day := func(d int) time.Time { return time.Date(2026, 11, d, 12, 0, 0, 0, time.UTC) }
	repoAt(t, filepath.Join(home, "Projects", "a"), "https://github.com/alice/a", day(1))
	repoAt(t, filepath.Join(home, "Projects", "topic", "b"), "git@github.com:alice/b.git", day(2))
	repoAt(t, filepath.Join(home, "Work", "c"), "https://github.com/acme/c.git", day(3))
	repoAt(t, filepath.Join(home, "generic", "e"), "https://github.com/bob/e", day(5))
	repoAt(t, filepath.Join(home, "Repos", "f"), "https://github.com/bob/f", day(1))
	writeNote(t, home, ".claude.json", `{"numStartups": 9007199254740993, "lastPrompt": "\ud83d <b>", "projects": {"/old": {"allowedTools": ["Bash"]}}}`)
	writeNote(t, home, ".codex/config.toml", "model = \"gpt\"\n\n[projects.\"/old\"]\ntrust_level = \"untrusted\"\n")
	writeNote(t, home, ".gemini/antigravity-cli/settings.json", `{"model": "Gemini 4 Neon (High)", "note": "a <b> c", "big": 9007199254740993, "trustedWorkspaces": ["/old"]}`)
	writeNote(t, home, "Projects/taken/notes.md", "")

	calls := filepath.Join(t.TempDir(), "calls")
	onPath(t, "gh", `echo "$*" >> `+calls+`
mkdir -p "$4/.git" && printf '[remote "origin"]\n\turl = https://github.com/%s\n' "$3" > "$4/.git/config"`)
	// A tmux server with sessions for Projects/busy and Games/fresh.
	onPath(t, "tmux", `[ "$2" = list-panes ] && printf 'Projects/busy\t11\t%%1\t\tzsh\t/elsewhere\t0\t0\t@1\t\tbusy\nGames/fresh\t11\t%%2\t\tzsh\t/elsewhere\t0\t0\t@2\t\tfresh\n'`)
	backend := func(string) mux.Backend { return mux.Detect(func(string) string { return "" }, "") }
	ws := func(words ...string) error { return run("project", words, backend) }
	cloned := func() string { data, _ := os.ReadFile(calls); return string(data) }

	if err := ws("alice/new"); err != nil {
		t.Fatal(err)
	}
	if want := "repo clone alice/new " + filepath.Join(home, "Projects", "new") + "\n"; cloned() != want {
		t.Errorf("alice/new ran gh %q, want %q, into the folder that holds most of alice's", cloned(), want)
	}
	if claude, codex, agy := trusted(t, filepath.Join(home, "Projects", "new")); !claude || !codex || !agy {
		t.Errorf("a clone from alice, whose repositories are here, is trusted by Claude Code %v, Codex %v and Antigravity %v", claude, codex, agy)
	}
	// bob has one repository in ~/generic and one in ~/Repos, and the one
	// in ~/generic moved last.
	if err := ws("https://github.com/bob/g"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(home, "generic", "g")); err != nil {
		t.Errorf("bob/g didn't go in ~/generic: %v", err)
	}
	// A repository already here only opens.
	before := cloned()
	if err := ws("acme/C"); err != nil || cloned() != before {
		t.Errorf("acme/C, already in ~/Work/c, gave %v and ran gh %q", err, strings.TrimPrefix(cloned(), before))
	}
	for _, words := range [][]string{{"carol/x"}, {"notes"}} {
		err := ws(words...)
		if err == nil || !strings.Contains(err.Error(), "--in") || !strings.Contains(err.Error(), "~/Projects") {
			t.Errorf("ws project %s gave %v, want it to ask for --in among the folders that hold repositories", words[0], err)
		}
	}
	if err := ws("alice/taken"); err == nil || !strings.Contains(err.Error(), "~/Projects/taken") || cloned() != before {
		t.Errorf("alice/taken, whose folder holds something else, gave %v and ran gh %q", err, strings.TrimPrefix(cloned(), before))
	}
	if cloned() != before {
		t.Fatal("ws project ran gh before it knew where to clone")
	}

	// open would go to the session named Projects/busy, so ws makes nothing,
	// while a session for Games/fresh does not block ~/Projects/fresh.
	if err := ws("alice/busy"); err == nil || !strings.Contains(err.Error(), "Projects/busy") || cloned() != before {
		t.Errorf("alice/busy, while a session named Projects/busy runs, gave %v and ran gh %q", err, strings.TrimPrefix(cloned(), before))
	}
	if err := ws("alice/fresh"); err != nil {
		t.Errorf("alice/fresh, while only Games/fresh runs, failed: %v", err)
	}
	// A trust that fails leaves nothing made, so trying again works.
	codexConfig := readNote(t, home, ".codex/config.toml")
	writeNote(t, home, ".codex/config.toml", "not = toml = at all")
	if err := ws("drafts", "--in", filepath.Join(home, "Projects")); err == nil {
		t.Error("ws project drafts made a project it couldn't trust")
	}
	if _, err := os.Stat(filepath.Join(home, "Projects", "drafts")); err == nil {
		t.Error("ws project drafts left its folder after it couldn't trust it")
	}
	writeNote(t, home, ".codex/config.toml", codexConfig)

	agyConfig := readNote(t, home, ".gemini/antigravity-cli/settings.json")
	writeNote(t, home, ".gemini/antigravity-cli/settings.json", `{"trustedWorkspaces": "not-an-array"}`)
	if err := ws("drafts", "--in", filepath.Join(home, "Projects")); err == nil {
		t.Error("ws project drafts made a project when Antigravity's settings were invalid")
	}
	if _, err := os.Stat(filepath.Join(home, "Projects", "drafts")); err == nil {
		t.Error("ws project drafts left its folder after Antigravity trust failed")
	}
	writeNote(t, home, ".gemini/antigravity-cli/settings.json", agyConfig)

	if err := ws("carol/x", "--in", filepath.Join(home, "Repos")); err != nil {
		t.Fatal(err)
	}
	if claude, codex, agy := trusted(t, filepath.Join(home, "Repos", "x")); claude || codex || agy {
		t.Error("a clone from carol, who has nothing here, is trusted")
	}
	notes := filepath.Join(home, "Projects", "notes")
	if err := ws("notes", "--in", filepath.Join(home, "Projects")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(notes, ".git")); err != nil {
		t.Errorf("notes isn't a git repository: %v", err)
	}
	if claude, codex, agy := trusted(t, notes); !claude || !codex || !agy {
		t.Errorf("a new project is trusted by Claude Code %v, Codex %v and Antigravity %v", claude, codex, agy)
	}
	// Trusting the same folder again does not duplicate its entry.
	notesReal, err := filepath.EvalSymlinks(notes)
	if err != nil {
		t.Fatal(err)
	}
	if err := trustFolder(notesReal); err != nil {
		t.Fatal(err)
	}
	// What else the configs hold stays as it was.
	if got := readNote(t, home, ".claude.json"); !strings.Contains(got, `"numStartups": 9007199254740993`) || !strings.Contains(got, `"lastPrompt": "\ud83d <b>"`) || !strings.Contains(got, `"allowedTools": [`) {
		t.Errorf("Claude Code's config lost what it held:\n%s", got)
	}
	if got := readNote(t, home, ".codex/config.toml"); !strings.Contains(got, `model = "gpt"`) || !strings.Contains(got, `trust_level = "untrusted"`) {
		t.Errorf("Codex's config lost what it held:\n%s", got)
	}
	if got := readNote(t, home, ".gemini/antigravity-cli/settings.json"); !strings.Contains(got, `"big": 9007199254740993`) ||
		!strings.Contains(got, `"note": "a <b> c"`) || !strings.Contains(got, `"/old"`) || strings.Count(got, notesReal) != 1 {
		t.Errorf("Antigravity's config lost what it held or duplicated %s:\n%s", notesReal, got)
	}
	// A missing Antigravity settings file is left absent.
	missingDir := t.TempDir()
	t.Setenv("ANTIGRAVITY_APP_DATA_DIR", missingDir)
	if err := trustFolder(notesReal); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(missingDir, "settings.json")); err == nil {
		t.Error("trustFolder created Antigravity's settings.json when it didn't exist")
	}
}

// ws waits while a Claude Code session holds its config's lock, and takes
// over a lock left untouched past proper-lockfile's 10 s.
func TestTrustWaitsForClaudeCodesLock(t *testing.T) {
	t.Setenv("CLAUDE_CONFIG_DIR", "")
	t.Setenv("CODEX_HOME", "")
	t.Setenv("ANTIGRAVITY_APP_DATA_DIR", "")
	oldHome := home
	home = t.TempDir()
	t.Cleanup(func() { home = oldHome })
	writeNote(t, home, ".claude.json", `{"projects": {}}`)
	writeNote(t, home, ".codex/config.toml", "")
	writeNote(t, home, ".gemini/antigravity-cli/settings.json", `{}`)
	dir := t.TempDir()
	lock := filepath.Join(home, ".claude.json.lock")

	if err := os.Mkdir(lock, 0o755); err != nil {
		t.Fatal(err)
	}
	done := make(chan error)
	root, err := filepath.EvalSymlinks(dir)
	if err != nil {
		t.Fatal(err)
	}
	go func() { done <- trustFolder(root) }()
	select {
	case err := <-done:
		t.Fatalf("ws wrote the config while a session held its lock (%v)", err)
	case <-time.After(300 * time.Millisecond):
	}
	os.Remove(lock) // the session finishes its write
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if claude, _, _ := trusted(t, dir); !claude {
		t.Error("the folder isn't trusted once the lock was free")
	}

	other := t.TempDir()
	if err := os.Mkdir(lock, 0o755); err != nil {
		t.Fatal(err)
	}
	long := time.Now().Add(-time.Minute)
	if err := os.Chtimes(lock, long, long); err != nil {
		t.Fatal(err)
	}
	if root, err = filepath.EvalSymlinks(other); err != nil {
		t.Fatal(err)
	}
	if err := trustFolder(root); err != nil {
		t.Fatal(err)
	}
	if claude, _, _ := trusted(t, other); !claude {
		t.Error("ws didn't take over a lock left for a minute")
	}
	if _, err := os.Stat(lock); err == nil {
		t.Error("ws left the lock behind")
	}
}
