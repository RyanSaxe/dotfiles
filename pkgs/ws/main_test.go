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
	if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+script+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
}

// withConfig gives ws a config that names agent, as the home switch writes
// it, and nothing when agent is "".
func withConfig(t *testing.T, agent string) {
	t.Helper()
	old := configDir
	configDir = t.TempDir()
	t.Cleanup(func() { configDir = old })
	if agent == "" {
		return
	}
	if err := os.WriteFile(filepath.Join(configDir, "config.toml"), []byte("agent = \""+agent+"\"\nopen_as = \"tab\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

// ws agent reports the agent the config names, with the model and effort
// that agent's own settings give it.
func TestAgentReadsEachAgentsOwnSettings(t *testing.T) {
	settings := t.TempDir()
	t.Setenv("CLAUDE_CONFIG_DIR", settings)
	t.Setenv("CODEX_HOME", settings)
	for name, text := range map[string]string{
		"settings.json": `{"model": "opus[1m]", "effortLevel": "medium", "theme": "dark"}`,
		"config.toml":   "model = \"gpt-6.1-sol\"\nmodel_reasoning_effort = \"high\"\n",
	} {
		if err := os.WriteFile(filepath.Join(settings, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for agent, want := range map[string]string{"claude": "opus[1m] medium", "codex": "gpt-6.1-sol high"} {
		withConfig(t, agent)
		named, err := defaultAgent()
		model, effort, settingsErr := agentSettings(named)
		if got := model + " " + effort; err != nil || settingsErr != nil || named != agent || got != want {
			t.Errorf("with %s configured: got %s with %s (%v, %v), want %s", agent, named, got, err, settingsErr, want)
		}
	}
	withConfig(t, "")
	if _, err := defaultAgent(); err == nil {
		t.Error("without a config, ws named an agent")
	}
}

// The worktrees popup asks for an agent and flags, either or both.
func TestPopupAnswerNamesAnAgentOrFlags(t *testing.T) {
	withConfig(t, "claude")
	for answer, want := range map[string]string{
		"":             "claude",
		"codex":        "codex",
		"--model opus": "claude --model opus",
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

// recorder is a multiplexer that ws runs inside, which records the panes of
// the session ws makes.
type recorder struct {
	mux.Backend
	panes []layout.Pane
}

func (r *recorder) Snapshot() (mux.Snapshot, error) { return mux.Snapshot{}, nil }
func (r *recorder) Inside() bool                    { return true }
func (r *recorder) Create(label, dir string, panes []layout.Pane) (string, error) {
	r.panes = panes
	return label, nil
}

// ws pr starts its agent as ws new does, with the agent, prompt and flags
// its words name, wherever its flags come. Without --agent, it is the agent
// the config names, with only the flags after --.
func TestNewAndPrStartTheAgentTheirFlagsName(t *testing.T) {
	for _, tool := range []string{"git", "rsync"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool, " is not installed")
		}
	}
	// A commit hook runs these tests, and ws new must not reach the
	// repository being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	repo := t.TempDir()
	for _, args := range [][]string{
		{"init", "-q", "-b", "main"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
	} {
		if _, err := git(repo, args...); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(repo)
	oldRoot, oldState, oldInteractive := worktreeRoot, stateDir, interactive
	worktreeRoot, stateDir, interactive = t.TempDir(), t.TempDir(), false
	t.Cleanup(func() { worktreeRoot, stateDir, interactive = oldRoot, oldState, oldInteractive })
	// gh shows pull request 5 on the branch feature, and its checkout does
	// nothing.
	onPath(t, "gh", "echo feature https://github.com/o/r/pull/5")
	withConfig(t, "claude")
	for _, tc := range []struct {
		words []string
		want  string
	}{
		{[]string{"new", "fix-login", "--agent", "codex", "--prompt", "fix it", "--", "-m", "gpt-6.1-sol"}, "codex -m gpt-6.1-sol -- 'fix it'"},
		{[]string{"pr", "--prompt", "fix it", "5", "--agent", "codex", "--", "-m", "gpt-6.1-sol"}, "codex -m gpt-6.1-sol -- 'fix it'"},
		{[]string{"new", "plain"}, "claude --"},
		{[]string{"new", "harder", "--", "--effort", "high"}, "claude --effort high --"},
	} {
		b := &recorder{}
		err := run(tc.words[0], tc.words[1:], func(string) mux.Backend { return b })
		if err != nil || len(b.panes) == 0 || b.panes[0].Run != tc.want {
			t.Errorf("ws %s made the panes %+v (%v), want an agent pane running %s", strings.Join(tc.words, " "), b.panes, err, tc.want)
		}
	}
}

// A squash merge leaves a branch git calls unmerged, so only GitHub can say
// its work landed.
func TestDeleteBranchAsksGitHubAboutUnmergedBranches(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	// A commit hook runs these tests, and the scratch repositories must not
	// be the one being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
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
		for _, args := range [][]string{
			{"init", "-q", "-b", "main"},
			{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
			{"checkout", "-q", "-b", "feature"},
			{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "squashed on GitHub"},
			{"checkout", "-q", "main"},
		} {
			if _, err := git(repo, args...); err != nil {
				t.Fatal(err)
			}
		}
		onPath(t, "gh", tc.gh)
		err := deleteBranch(repo, "feature", tc.force)
		_, missing := git(repo, "rev-parse", "--verify", "-q", "refs/heads/feature")
		if deleted := missing != nil; deleted != tc.deleted || (err == nil) != tc.deleted {
			t.Errorf("%s: deleted is %v (%v), want %v", tc.name, deleted, err, tc.deleted)
		}
	}
}

// An agent option that takes several values, such as claude's --add-dir,
// takes every word after it that isn't an option, so the agent layout ends
// the options before the prompt.
func TestAgentLayoutKeepsThePromptOutOfTheFlags(t *testing.T) {
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("zsh is not installed")
	}
	for prompt, want := range map[string]string{
		"fix the bug": "[--add-dir][/notes][--][fix the bug]",
		"":            "[--add-dir][/notes][--]",
	} {
		vars := map[string][]string{"{agent}": {"claude", "--add-dir", "/notes"}, "{prompt}": nil}
		if prompt != "" {
			vars["{prompt}"] = []string{prompt}
		}
		panes, err := layout.Load(t.TempDir(), "agent", builtinLayouts, vars)
		if err != nil {
			t.Fatal(err)
		}
		out, err := exec.Command(zsh, "-f", "-c", `claude() { printf '[%s]' "$@" }; `+panes[0].Run).Output()
		if err != nil || string(out) != want {
			t.Errorf("prompt %q: claude got %s (%v), want %s", prompt, out, err, want)
		}
	}
}

// A ws new that can't start its agent leaves no worktree or branch behind:
// a missing config, an unknown agent, a session already running under the
// worktree's name, and ignored files that can't be copied.
func TestAFailedNewWorktreeLeavesNothingBehind(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	// A commit hook runs these tests, and ws new must not reach the
	// repository being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	repo := t.TempDir()
	for _, args := range [][]string{
		{"init", "-q", "-b", "main"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
	} {
		if _, err := git(repo, args...); err != nil {
			t.Fatal(err)
		}
	}
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	project := filepath.Base(repo)
	onPath(t, "tmux", `[ "$2" = list-panes ] && printf '`+project+`/taken\t11\t%%1\tagent\tclaude\t/elsewhere\t0\t0\tclaude\n'`)
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
	withConfig(t, "")
	failsToStart("no-config", start{layout: "agent"})
	withConfig(t, "claude")
	failsToStart("fix-login", start{layout: "agent", agent: "opus"})
	failsToStart("taken", start{layout: "agent"})
	onPath(t, "rsync", "exit 1")
	failsToStart("no-copy", start{layout: "agent"})
}

// A ws pr that can't copy the ignored files removes its worktree, so the next
// ws pr checks the pull request out afresh instead of opening a worktree
// without them. It keeps the branch, which gh pr checkout may have reused.
func TestAFailedPullRequestCopyRemovesItsWorktree(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	// A commit hook runs these tests, and ws pr must not reach the
	// repository being committed to.
	for _, v := range gitHookEnv {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	repo := t.TempDir()
	for _, args := range [][]string{
		{"init", "-q", "-b", "main"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--allow-empty", "-m", "base"},
		{"branch", "feature"}, // the pull request's branch, already local
	} {
		if _, err := git(repo, args...); err != nil {
			t.Fatal(err)
		}
	}
	oldRoot := worktreeRoot
	worktreeRoot = t.TempDir()
	t.Cleanup(func() { worktreeRoot = oldRoot })
	onPath(t, "gh", `case "$2" in
view) echo "feature https://github.com/o/r/pull/7";;
checkout) git checkout -q feature;;
esac`)
	onPath(t, "rsync", "exit 1")
	withConfig(t, "claude")
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
