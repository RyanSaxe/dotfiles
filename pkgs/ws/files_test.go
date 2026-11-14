package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"testing"
)

func TestFilesTabsEachListTheirOwnKind(t *testing.T) {
	for _, tool := range []string{"git", "fd"} {
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
	for file, content := range map[string]string{
		"main.go":         "package main",
		"my notes.md":     "a name with a space",
		".env.example":    "hidden",
		"build/out.bin":   "ignored",
		".gitignore":      "build/\n.cache/\n",
		".cache/tmp.json": "hidden and ignored",
	} {
		path := filepath.Join(dir, file)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	p := filesPopup(nil, dir)
	for tab, want := range [][]string{
		{"main.go", "my notes.md"},
		{".env.example", ".gitignore"},
		{".cache/tmp.json", "build/out.bin"},
	} {
		rows, err := p.Load(tab)
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
