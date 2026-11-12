package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
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
	if err := setAgent("codex"); err != nil || defaultAgent() != "codex" {
		t.Errorf("after setting codex: got %s (%v), want codex", defaultAgent(), err)
	}
	if err := setAgent("nope"); err == nil || defaultAgent() != "codex" {
		t.Errorf("setting an unknown agent: got %s (%v), want an error and codex kept", defaultAgent(), err)
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
