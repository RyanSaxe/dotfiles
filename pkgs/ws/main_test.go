package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"workspace/layout"
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

func TestDefaultAgent(t *testing.T) {
	stateDir = t.TempDir()
	t.Setenv("PATH", "")
	if got := defaultAgent(); got != "codex" {
		t.Errorf("without claude installed: got %s, want codex", got)
	}
	onPath(t, "claude", "")
	if got := defaultAgent(); got != "claude" {
		t.Errorf("with claude installed: got %s, want claude", got)
	}
	if err := setAgent("codex", nil); err != nil || defaultAgent() != "codex" {
		t.Errorf("after setting codex: got %s (%v), want codex", defaultAgent(), err)
	}
	if err := setAgent("nope", nil); err == nil || defaultAgent() != "codex" {
		t.Errorf("setting an unknown agent: got %s (%v), want an error and codex kept", defaultAgent(), err)
	}
}

// Each agent keeps its own defaults, and a command's own flags replace them.
func TestAgentCommandUsesEachAgentsDefaults(t *testing.T) {
	stateDir = t.TempDir()
	onPath(t, "claude", "")
	for _, tc := range []struct {
		name         string
		set          string // the agent ws agent sets, when not empty
		setWords     []string
		agent, flags string // what the command names, split at spaces
		want         string
	}{
		{"saved defaults", "claude", []string{"--effort", "medium"}, "", "", "claude --effort medium"},
		{"own flags replace them", "", nil, "", "--model opus", "claude --model opus"},
		{"another agent has none yet", "", nil, "codex", "", "codex"},
		{"its own defaults", "codex", []string{"-c", "x=1"}, "", "", "codex -c x=1"},
		{"switching keeps claude's", "", nil, "claude", "", "claude --effort medium"},
		{"switching back keeps both", "claude", nil, "codex", "", "codex -c x=1"},
		{"a -- before them", "claude", []string{"--", "--effort", "low"}, "", "", "claude --effort low"},
		{"a -- alone clears them", "claude", []string{"--"}, "", "", "claude"},
	} {
		if tc.set != "" {
			if err := setAgent(tc.set, tc.setWords); err != nil {
				t.Fatal(err)
			}
		}
		if got := strings.Join(agentCommand(tc.agent, strings.Fields(tc.flags)), " "); got != tc.want {
			t.Errorf("%s: got %s, want %s", tc.name, got, tc.want)
		}
	}
}

// The worktrees popup asks for an agent and flags, either or both.
func TestPopupAnswerNamesAnAgentOrFlags(t *testing.T) {
	stateDir = t.TempDir()
	onPath(t, "claude", "")
	if err := setAgent("claude", []string{"--effort", "medium"}); err != nil {
		t.Fatal(err)
	}
	for answer, want := range map[string]string{
		"":             "claude --effort medium",
		"codex":        "codex",
		"--model opus": "claude --model opus",
		`claude --append-system-prompt "be brief"`: "claude --append-system-prompt 'be brief'",
	} {
		s, err := startFromAnswer(answer)
		if got := layout.Line(agentCommand(s.agent, s.flags)); err != nil || got != want {
			t.Errorf("%q starts %s (%v), want %s", answer, got, err, want)
		}
	}
	if _, err := startFromAnswer("--model opus; --effort high"); err == nil {
		t.Error("the popup dropped the words after an unquoted ; without saying so")
	}
}

// ws COMMAND --help prints the command's own usage.
func TestEveryCommandHasItsOwnHelp(t *testing.T) {
	for cmd := range commandArgs {
		if commandUsage(cmd) == "" {
			t.Errorf("ws %s --help has no usage of its own", cmd)
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

func TestNewWorktreeRefusesAnUnknownAgent(t *testing.T) {
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
	worktreeRoot = t.TempDir()
	if err := newWorktree(nil, repo, "fix-login", "", start{layout: "agent", agent: "opus"}); err == nil {
		t.Error("ws new made a worktree for the agent opus")
	}
	if made, _ := os.ReadDir(worktreeRoot); len(made) > 0 {
		t.Errorf("ws new left %d folders under the worktree root", len(made))
	}
}
