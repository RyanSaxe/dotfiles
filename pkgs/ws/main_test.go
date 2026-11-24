package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"workspace/layout"
	"workspace/mux"
)

// onPath puts a script named name first on PATH.
func onPath(t *testing.T, name, script string) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+script+"\n"), 0o700); err != nil { //nolint:gosec // test helper writes executable shim script to temp PATH
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
}

// requireTools skips the test when any required binary isn't on PATH.
func requireTools(t *testing.T, tools ...string) {
	t.Helper()
	for _, tool := range tools {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool + " is not installed")
		}
	}
}

// clearGitHookEnv unsets git's hook environment variables so scratch
// repositories in tests never reach the checkout running a commit hook.
func clearGitHookEnv(t *testing.T) {
	t.Helper()
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		if err := os.Unsetenv(v); err != nil {
			t.Fatal(err)
		}
	}
}

func runGitSteps(t *testing.T, dir string, steps ...[]string) {
	t.Helper()
	for _, args := range steps {
		if _, err := git(dir, args...); err != nil {
			t.Fatal(err)
		}
	}
}

func initBaseRepo(t *testing.T, dir string, extra ...[]string) {
	t.Helper()
	steps := append([][]string{
		{"init", "-q", "-b", "main"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
	}, extra...)
	runGitSteps(t, dir, steps...)
}

// withConfig gives ws a config that names agent and open_as, as the home
// switch writes it, and nothing when agent is "".
func withConfig(t *testing.T, agent, openAs string) {
	t.Helper()
	old := configDir
	configDir = t.TempDir()
	t.Cleanup(func() { configDir = old })
	if agent == "" {
		return
	}
	if err := os.WriteFile(filepath.Join(configDir, "config.toml"), []byte("agent = \""+agent+"\"\nopen_as = \""+openAs+"\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}

// ws agent reports the agent the config names, with the model and effort
// that agent's own settings give it.
func TestAgentReadsEachAgentsOwnSettings(t *testing.T) {
	claudeDir, codexDir, agyDir := t.TempDir(), t.TempDir(), t.TempDir()
	t.Setenv("CLAUDE_CONFIG_DIR", claudeDir)
	t.Setenv("CODEX_HOME", codexDir)
	t.Setenv("ANTIGRAVITY_APP_DATA_DIR", agyDir)
	writeNote(t, claudeDir, "settings.json", `{"model": "opus[1m]", "effortLevel": "medium", "theme": "dark"}`)
	writeNote(t, codexDir, "config.toml", "model = \"gpt-6.1-sol\"\nmodel_reasoning_effort = \"high\"\n")
	writeNote(t, agyDir, "settings.json", `{"model": "Gemini 4 Neon (High)", "theme": "dark"}`)
	for agent, want := range map[string]string{
		"claude": "opus[1m] medium",
		"codex":  "gpt-6.1-sol high",
		"agy":    "Gemini 4 Neon high",
	} {
		withConfig(t, agent, "tab")
		named, err := defaultAgent()
		model, effort, settingsErr := agentSettings(named)
		if got := model + " " + effort; err != nil || settingsErr != nil || named != agent || got != want {
			t.Errorf("with %s configured: got %s with %s (%v, %v), want %s", agent, named, got, err, settingsErr, want)
		}
	}
	// An Antigravity model whose parenthesized suffix is not an effort level
	// keeps its full label with no effort.
	writeNote(t, agyDir, "settings.json", `{"model": "Orchestrator (Neon)"}`)
	if model, effort, err := agentSettings("agy"); err != nil || model != "Orchestrator (Neon)" || effort != "" {
		t.Errorf("with Orchestrator (Neon): got %q %q (%v), want %q %q", model, effort, err, "Orchestrator (Neon)", "")
	}
	withConfig(t, "", "")
	if _, err := defaultAgent(); err == nil {
		t.Error("without a config, ws named an agent")
	}
}

// Ctrl-T on the go popup's Worktrees tab asks for an agent and flags,
// either or both.
func TestPopupAnswerNamesAnAgentOrFlags(t *testing.T) {
	withConfig(t, "claude", "tab")
	for answer, want := range map[string]string{
		"":                  "claude",
		"codex":             "codex",
		"agy --effort high": "agy --effort high",
		"--model opus":      "claude --model opus",
		`claude --append-system-prompt "be brief"`: "claude --append-system-prompt 'be brief'",
	} {
		s, err := startFromAnswer(answer)
		var words []string
		if err == nil {
			words, err = agentCommand(s.agent, s.flags)
		}
		if got := layout.Line(words); err != nil || got != want {
			t.Errorf("%q starts %s (%v), want %s", answer, got, err, want)
		}
	}
	if _, err := startFromAnswer("--model opus; --effort high"); err == nil {
		t.Error("the popup dropped the words after an unquoted ; without saying so")
	}
}

// A command refuses a flag it doesn't take, rather than run without it.
func TestCommandsTakeOnlyTheirOwnFlags(t *testing.T) {
	for _, c := range commands {
		for _, other := range commands {
			for _, o := range other.flags {
				words := append(slices.Repeat([]string{"x"}, len(strings.Fields(c.args))), "--"+o.name)
				if o.value != "" {
					words = append(words, "v")
				}
				_, err := c.parse(words)
				takes := slices.ContainsFunc(c.flags, func(f option) bool { return f.name == o.name })
				if takes != (err == nil) {
					t.Errorf("ws %s %s: got error %v, want one only for a flag it doesn't take", c.name, strings.Join(words, " "), err)
				}
			}
		}
	}
}

// recorder is a multiplexer that ws runs inside, with the sessions and panes
// of snapshot, which records each session and tab ws makes.
type recorder struct {
	mux.Backend
	snapshot mux.Snapshot
	made     []made
	tabs     [][]string // each tab ws ran a command in: the place's label, the folder, then the command
}

func (r *recorder) Tab(p mux.Place, dir string, args ...string) (mux.Place, error) {
	r.tabs = append(r.tabs, append([]string{p.Label, dir}, args...))
	return mux.Place{Label: p.Label, Session: p.Session, Tab: "tab:new", Named: p.Named}, nil
}

// made is a session or tab ws made: its label, the session a tab is in, its
// folder and its panes.
type made struct {
	label, in, dir string
	panes          []layout.Pane
}

func (m made) String() string {
	what := "session " + m.label
	if m.in != "" {
		what = "tab " + m.label + " of " + m.in
	}
	if len(m.panes) == 1 && m.panes[0].Run == "" {
		what += ", a plain shell,"
	}
	return what + " in " + m.dir
}

func (r *recorder) Snapshot() (mux.Snapshot, error) { return r.snapshot, nil }
func (r *recorder) Inside() bool                    { return true }
func (r *recorder) Create(label, dir string, panes []layout.Pane) (mux.Place, error) {
	r.made = append(r.made, made{label: label, dir: dir, panes: panes})
	return mux.Place{Label: label, Session: "session:" + label, Whole: true}, nil
}

func (r *recorder) CreateTab(session, name, dir string, panes []layout.Pane) (mux.Place, error) {
	r.made = append(r.made, made{label: name, in: session, dir: dir, panes: panes})
	return mux.Place{Label: name, Session: session, Tab: "tab:" + name, Named: name != ""}, nil
}

// lastPanes are the panes of the last session or tab ws made.
func (r *recorder) lastPanes() []layout.Pane {
	if len(r.made) == 0 {
		return nil
	}
	return r.made[len(r.made)-1].panes
}

func (r *recorder) madeStrings() []string {
	got := make([]string, len(r.made))
	for i, m := range r.made {
		got[i] = m.String()
	}
	return got
}

// ws pr starts its agent as ws new does, with the agent, prompt and flags
// its words name, wherever its flags come. Without --agent, it is the agent
// the config names, with only the flags after --.
func TestNewAndPrStartTheAgentTheirFlagsName(t *testing.T) {
	requireTools(t, "git", "rsync")
	clearGitHookEnv(t)
	repo := t.TempDir()
	initBaseRepo(t, repo)
	t.Chdir(repo)
	oldRoot, oldState, oldInteractive := worktreeRoot, stateDir, interactive
	worktreeRoot, stateDir, interactive = t.TempDir(), t.TempDir(), false
	t.Cleanup(func() { worktreeRoot, stateDir, interactive = oldRoot, oldState, oldInteractive })
	// gh shows pull request N on a branch of its own, and its checkout does
	// nothing.
	onPath(t, "gh", `echo "feature-$3 https://github.com/o/r/pull/$3"`)
	withConfig(t, "claude", "tab")
	for _, tc := range []struct {
		words []string
		want  string
	}{
		{[]string{"new", "fix-login", "--agent", "codex", "--prompt", "fix it", "--", "-m", "gpt-6.1-sol"}, "codex -m gpt-6.1-sol -- 'fix it'"},
		{[]string{"pr", "--prompt", "fix it", "5", "--agent", "codex", "--", "-m", "gpt-6.1-sol"}, "codex -m gpt-6.1-sol -- 'fix it'"},
		{[]string{"new", "fix-agy", "--agent", "agy", "--prompt", "fix it", "--", "--effort", "high"}, "agy --effort high -i 'fix it'"},
		{[]string{"pr", "--prompt", "fix it", "6", "--agent", "agy", "--", "--effort", "high"}, "agy --effort high -i 'fix it'"},
		{[]string{"new", "plain-agy", "--agent", "agy"}, "agy"},
		{[]string{"new", "plain"}, "claude"},
		{[]string{"new", "harder", "--", "--effort", "high"}, "claude --effort high"},
	} {
		b := &recorder{}
		err := run(tc.words[0], tc.words[1:], func(string) mux.Backend { return b })
		if panes := b.lastPanes(); err != nil || len(panes) == 0 || panes[0].Run != tc.want {
			t.Errorf("ws %s made the panes %+v (%v), want an agent pane running %s", strings.Join(tc.words, " "), panes, err, tc.want)
		}
	}
}

// A worktree opens as the config's open_as says, unless --tab or --session
// says otherwise. As a tab, it is named after the worktree in its project's
// session, which ws starts as a plain shell in the main checkout when there
// is none. Any other folder opens as a session, even as a tab, such as one
// in a worktree's spot that git doesn't check out.
func TestAWorktreeOpensAsATabOrASession(t *testing.T) {
	requireTools(t, "git", "rsync")
	clearGitHookEnv(t)
	repo := t.TempDir()
	initBaseRepo(t, repo)
	main, err := mainCheckout(repo)
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(repo)
	oldRoot, oldInteractive := worktreeRoot, interactive
	worktreeRoot, interactive = t.TempDir(), false
	t.Cleanup(func() { worktreeRoot, interactive = oldRoot, oldInteractive })
	project := filepath.Base(main)
	session := labelFor(main)
	root := filepath.Join(worktreeRoot, project)
	// A folder in a worktree's spot that git doesn't check out.
	if err := os.MkdirAll(filepath.Join(root, "plain"), 0o750); err != nil {
		t.Fatal(err)
	}
	opened := mux.Snapshot{Sessions: []mux.Session{{ID: "session:" + session, Label: session}}}
	for _, tc := range []struct {
		openAs   string // the config's
		words    []string
		snapshot mux.Snapshot
		want     []string
	}{
		{"tab", []string{"new", "one"}, mux.Snapshot{}, []string{
			"session " + session + ", a plain shell, in " + main,
			"tab " + project + "/one of session:" + session + " in " + root + "/one",
		}},
		{"tab", []string{"new", "two"}, opened, []string{"tab " + project + "/two of session:" + session + " in " + root + "/two"}},
		{"tab", []string{"new", "three", "--session"}, opened, []string{"session " + project + "/three in " + root + "/three"}},
		{"session", []string{"new", "four"}, opened, []string{"session " + project + "/four in " + root + "/four"}},
		{"session", []string{"new", "five", "--tab"}, opened, []string{"tab " + project + "/five of session:" + session + " in " + root + "/five"}},
		{"tab", []string{"open", main}, mux.Snapshot{}, []string{"session " + session + " in " + main}},
		{"tab", []string{"open", root + "/plain"}, opened, []string{"session " + project + "/plain in " + root + "/plain"}},
	} {
		withConfig(t, "claude", tc.openAs)
		b := &recorder{snapshot: tc.snapshot}
		err := run(tc.words[0], tc.words[1:], func(string) mux.Backend { return b })
		if got := b.madeStrings(); err != nil || !slices.Equal(got, tc.want) {
			t.Errorf("with open_as %s, ws %s made %q (%v), want %q", tc.openAs, strings.Join(tc.words, " "), got, err, tc.want)
		}
	}
	withConfig(t, "claude", "tab")
	if err := run("new", []string{"six", "--tab", "--session"}, func(string) mux.Backend { return &recorder{} }); err == nil {
		t.Error("ws new six --tab --session made a worktree")
	}
}

// ws tab runs its command, word for word, in a new tab of the folder's
// place, and makes the place with the command typed into its shell when the
// folder has none. Run by an agent, it shows nothing, and the recorder has
// no Show to call.
type tabTestFixture struct {
	session, project, main, fix string
	command, words              []string
}

func TestTabRunsItsCommandInTheFoldersPlace(t *testing.T) {
	requireTools(t, "git")
	clearGitHookEnv(t)
	oldRoot, oldInteractive := worktreeRoot, interactive
	worktreeRoot, interactive = t.TempDir(), false
	t.Cleanup(func() { worktreeRoot, interactive = oldRoot, oldInteractive })
	repo := t.TempDir()
	main, err := filepath.EvalSymlinks(repo) // git reports the real path
	if err != nil {
		t.Fatal(err)
	}
	project, session := filepath.Base(main), labelFor(main)
	fix := filepath.Join(worktreeRoot, project, "fix")
	initBaseRepo(t, repo, []string{"worktree", "add", "-q", "-b", "fix", fix})
	withConfig(t, "claude", "tab")
	command := []string{"env", "A=b c", "claude", "--effort", "high"}
	fx := tabTestFixture{
		session: session, project: project, main: main, fix: fix,
		command: command, words: append([]string{fix, "--"}, command...),
	}
	fx.checkOpenWorktree(t)
	fx.checkClosedWorktree(t)
	if err := run("tab", []string{fix}, func(string) mux.Backend { return &recorder{} }); err == nil {
		t.Error("ws tab with no command after -- ran")
	}
}

func (fx tabTestFixture) checkOpenWorktree(t *testing.T) {
	t.Helper()
	open := &recorder{snapshot: mux.Snapshot{
		Sessions: []mux.Session{{ID: "session:" + fx.session, Label: fx.session}},
		Panes:    []mux.Pane{{Session: "session:" + fx.session, Label: fx.session, ID: "pane", Tab: "tab:fix", TabName: fx.project + "/fix", Focused: true}},
	}}
	if err := run("tab", fx.words, func(string) mux.Backend { return open }); err != nil || len(open.made) > 0 ||
		len(open.tabs) != 1 || !slices.Equal(open.tabs[0], append([]string{fx.project + "/fix", fx.fix}, fx.command...)) {
		t.Errorf("ws tab on an open worktree made %v and ran %q (%v), want one tab of %s/fix running %q", open.made, open.tabs, err, fx.project, fx.command)
	}
}

func (fx tabTestFixture) checkClosedWorktree(t *testing.T) {
	t.Helper()
	closed := &recorder{}
	err := run("tab", fx.words, func(string) mux.Backend { return closed })
	want := []string{"session " + fx.session + ", a plain shell, in " + fx.main, "tab " + fx.project + "/fix of session:" + fx.session + " in " + fx.fix}
	if got := closed.madeStrings(); err != nil || len(closed.tabs) > 0 || !slices.Equal(got, want) || closed.lastPanes()[0].Run != layout.Line(fx.command) {
		t.Errorf("ws tab on a closed worktree made %q with %+v (%v), want %q running %s", got, closed.lastPanes(), err, want, layout.Line(fx.command))
	}
}

// A squash merge leaves a branch git calls unmerged, so only GitHub can say
// its work landed.
func TestDeleteBranchAsksGitHubAboutUnmergedBranches(t *testing.T) {
	requireTools(t, "git")
	clearGitHookEnv(t)
	for _, tc := range []struct {
		name, gh string
		force    bool
		deleted  bool
	}{
		{"a merged pull request", "echo MERGED", false, true},
		{"an open pull request", "echo OPEN", false, false},
		{"a closed pull request", "echo CLOSED", false, false},
		{"no pull request", "echo 'no pull requests found' >&2; exit 1", false, false},
		{"force with no pull request", "exit 1", true, true},
	} {
		repo := t.TempDir()
		initBaseRepo(t, repo,
			[]string{"checkout", "-q", "-b", "feature"},
			[]string{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "squashed on GitHub"},
			[]string{"checkout", "-q", "main"},
		)
		onPath(t, "gh", tc.gh)
		err := deleteBranch(repo, "feature", tc.force)
		_, missing := git(repo, "rev-parse", "--verify", "-q", "refs/heads/feature")
		if deleted := missing != nil; deleted != tc.deleted || (err == nil) != tc.deleted {
			t.Errorf("%s: deleted is %v (%v), want %v", tc.name, deleted, err, tc.deleted)
		}
	}
}

// An agent option that takes several values, such as claude's --add-dir,
// takes every word after it that isn't an option, so claude and codex end
// their options with -- before a prompt, while agy passes it with -i.
func TestAgentLayoutKeepsThePromptOutOfTheFlags(t *testing.T) {
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("zsh is not installed")
	}
	for _, tc := range []struct {
		agent, prompt, want string
	}{
		{"claude", "fix the bug", "[--add-dir][/notes][--][fix the bug]"},
		{"claude", "", "[--add-dir][/notes]"},
		{"agy", "fix the bug", "[--add-dir][/notes][-i][fix the bug]"},
		{"agy", "", "[--add-dir][/notes]"},
	} {
		vars := map[string][]string{"{agent}": {tc.agent, "--add-dir", "/notes"}, "{prompt}": agentPrompt(tc.agent, tc.prompt)}
		panes, err := layout.Load(t.TempDir(), "agent", builtinLayouts, vars)
		if err != nil {
			t.Fatal(err)
		}
		out, err := exec.Command(zsh, "-f", "-c", tc.agent+`() { printf '[%s]' "$@" }; `+panes[0].Run).Output() //nolint:gosec // test verifies layout command parsing in local zsh
		if err != nil || string(out) != tc.want {
			t.Errorf("%s prompt %q: got %s (%v), want %s", tc.agent, tc.prompt, out, err, tc.want)
		}
	}
}

// A ws new that can't start its agent leaves no worktree or branch behind:
// a missing config, an unknown agent, a session already running under the
// worktree's name, and ignored files that can't be copied.
func TestAFailedNewWorktreeLeavesNothingBehind(t *testing.T) {
	requireTools(t, "git")
	clearGitHookEnv(t)
	repo := t.TempDir()
	initBaseRepo(t, repo)
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	project := filepath.Base(repo)
	onPath(t, "tmux", `[ "$2" = list-panes ] && printf '`+project+`/taken\t11\t%%1\tagent\tclaude\t/elsewhere\t0\t0\t@1\t\tclaude\n'`)
	b := mux.Detect(func(k string) string { return map[string]string{"TMUX": "/tmp/tmux-501/default,1,0"}[k] }, "")
	failsToStart := func(name string, s start) {
		t.Helper()
		if err := newWorktree(b, repo, name, "", s); err == nil {
			t.Errorf("ws new %s succeeded", name)
		}
		if _, err := os.Stat(filepath.Join(worktreeRoot, project, name)); err == nil {
			t.Errorf("ws new %s left its worktree", name)
		}
		if _, err := git(repo, "rev-parse", "--verify", "-q", "refs/heads/"+name); err == nil {
			t.Errorf("ws new %s left its branch", name)
		}
	}
	withConfig(t, "", "")
	failsToStart("no-config", start{layout: "agent"})
	withConfig(t, "claude", "tab")
	failsToStart("fix-login", start{layout: "agent", agent: "opus"})
	failsToStart("taken", start{layout: "agent"})
	onPath(t, "rsync", "exit 1")
	failsToStart("no-copy", start{layout: "agent"})
}

// A ws pr that can't copy the ignored files removes its worktree, so the next
// ws pr checks the pull request out afresh instead of opening a worktree
// without them. It keeps the branch, which gh pr checkout may have reused.
func TestAFailedPullRequestCopyRemovesItsWorktree(t *testing.T) {
	requireTools(t, "git")
	clearGitHookEnv(t)
	repo := t.TempDir()
	initBaseRepo(t, repo, []string{"branch", "feature"}) // the pull request's branch, already local
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	onPath(t, "gh", `case "$2" in
view) echo "feature https://github.com/o/r/pull/7";;
checkout) git checkout -q feature;;
esac`)
	onPath(t, "rsync", "exit 1")
	withConfig(t, "claude", "tab")
	if _, err := pullRequest(nil, repo, "7", start{layout: "review"}); err == nil {
		t.Error("ws pr 7 succeeded")
	}
	if dir := checkedOut(repo, "feature"); dir != "" {
		t.Errorf("ws pr 7 left the pull request checked out in %s", dir)
	}
	if _, err := git(repo, "rev-parse", "--verify", "-q", "refs/heads/feature"); err != nil {
		t.Error("ws pr 7 deleted the branch feature")
	}
}
