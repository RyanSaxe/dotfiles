package main

import (
	"slices"
	"testing"
)

func TestFilesTabsEachListTheirOwnKind(t *testing.T) {
	requireTools(t, "git", "fd")
	clearGitHookEnv(t)
	dir := t.TempDir()
	if _, err := git(dir, "init", "-q"); err != nil {
		t.Fatalf("git init: %v", err)
	}
	for file, content := range map[string]string{
		"main.go":         "package main",
		"my notes.md":     "a name with a space",
		".env.example":    "hidden",
		"build/out.bin":   "ignored",
		".gitignore":      "build/\n.cache/\n",
		".cache/tmp.json": "hidden and ignored",
	} {
		writeNote(t, dir, file, content)
	}

	p := filesPopup(nil, dir)
	for tab, want := range [][]string{
		{"main.go", "my notes.md"},
		{".env.example", ".gitignore"},
		{".cache/tmp.json", "build/out.bin"},
	} {
		rows, err := p.Load(tab, nil)
		if err != nil {
			t.Fatalf("tab %s: %v", p.Tabs[tab].Name, err)
		}
		var got []string
		for _, r := range rows {
			got = append(got, r.ID)
		}
		slices.Sort(got)
		if !slices.Equal(got, want) {
			t.Errorf("tab %s lists %q, want %q", p.Tabs[tab].Name, got, want)
		}
	}
}
