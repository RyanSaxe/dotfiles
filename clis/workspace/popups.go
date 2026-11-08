package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"

	tea "github.com/charmbracelet/bubbletea"
)

func pick(name string) error {
	popups := map[string]func() popup{"reviews": reviewsPopup}
	build, ok := popups[name]
	if !ok {
		return fmt.Errorf("no popup named %s, only reviews", name)
	}
	_, err := tea.NewProgram(newFrame(build()), tea.WithAltScreen()).Run()
	return err
}

// repos finds git checkouts under the project folders as zsh's `to` does. It
// stops at a repository, since nothing inside one is a separate project, and
// never reaches ~/worktrees, which is outside every project folder.
func repos() []string {
	var found []string
	var walk func(string)
	walk = func(dir string) {
		entries, _ := os.ReadDir(dir)
		for _, e := range entries {
			if p := filepath.Join(dir, e.Name()); e.IsDir() {
				if _, err := os.Stat(filepath.Join(p, ".git")); err == nil {
					found = append(found, p)
				} else {
					walk(p)
				}
			}
		}
	}
	var roots []os.FileInfo
	for _, name := range []string{"work", "Projects", "projects", "generic", "repositories"} {
		// ~/Projects and ~/projects are one folder on a case-insensitive disk.
		info, err := os.Stat(filepath.Join(home, name))
		if err == nil && !slices.ContainsFunc(roots, func(r os.FileInfo) bool { return os.SameFile(r, info) }) {
			roots = append(roots, info)
			walk(filepath.Join(home, name))
		}
	}
	return found
}
