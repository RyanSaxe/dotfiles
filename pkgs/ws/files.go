package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

// filesPopup lists dir's files as fd finds them, one kind per tab: the
// files, then only the hidden ones, then only what git ignores.
func filesPopup(b mux.Backend, dir string) popup.Popup {
	// Each tab's fd flags let in more than the tab before, and the tab shows
	// only what they add.
	flags := [][]string{nil, {"--hidden"}, {"--hidden", "--no-ignore"}}
	find := func(extra []string) ([]string, error) {
		out, err := runIn(dir, "fd", append([]string{"--type", "f", "--strip-cwd-prefix", "--exclude", ".git"}, extra...)...)
		var files []string
		for f := range strings.SplitSeq(out, "\n") {
			if f != "" {
				files = append(files, f)
			}
		}
		return files, err
	}
	return popup.Popup{
		Noun: "files", OneLine: true,
		Tabs: []popup.Tab{{Name: "Files", Empty: "No files."}, {Name: "Hidden", Empty: "No hidden files."}, {Name: "Ignored", Empty: "No ignored files."}},
		Load: func(t int) ([]popup.Row, error) {
			files, err := find(flags[t])
			if err == nil && t > 0 {
				var before []string
				before, err = find(flags[t-1])
				files = without(files, before)
			}
			changed := gitChanges(dir)
			var rows []popup.Row
			for _, f := range files {
				r := popup.Row{ID: f, Title: f, Tag: changed[f]}
				if info, err := os.Stat(filepath.Join(dir, f)); err == nil {
					r.Qualifier = relAge(info.ModTime())
				}
				rows = append(rows, r)
			}
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			return runIn(dir, "bat", "--color=always", "--style=numbers", "--line-range=:500", r.ID)
		},
		Actions: []popup.Action{{Key: "enter", Help: "edit", Run: func(r popup.Row) tea.Cmd {
			return popup.Do(func() error { return openFile(b, dir, filepath.Join(dir, r.ID)) }, popup.Quit)
		}}},
	}
}

// gitChanges tags the files git sees as changed in dir: modified, new to
// git, or added.
func gitChanges(dir string) map[string]lipgloss.Style {
	out, _ := runIn(dir, "git", "status", "--porcelain", "--untracked-files=all")
	tags := map[string]lipgloss.Style{}
	for line := range strings.SplitSeq(out, "\n") {
		if len(line) < 4 {
			continue
		}
		code, file := line[:2], line[3:]
		if _, renamed, ok := strings.Cut(file, " -> "); ok {
			file = renamed
		}
		switch {
		case code == "??":
			tags[file] = popup.Green.SetString("new")
		case strings.Contains(code, "A"):
			tags[file] = popup.Green.SetString("added")
		case strings.Contains(code, "M"), strings.Contains(code, "R"):
			tags[file] = popup.Yellow.SetString("modified")
		}
	}
	return tags
}

// openFile opens file in Neovim in a new tab of dir's session, or starts the
// session with it.
func openFile(b mux.Backend, dir, file string) error {
	id, err := mux.Find(b, labelFor(dir))
	if err != nil {
		return err
	}
	if id == "" {
		return open(b, dir, start{layout: "file", file: file}, true)
	}
	if err := b.Tab(id, dir, "nvim", file); err != nil {
		return err
	}
	return b.Show(id)
}

// without is files minus every name in drop, in files' order.
func without(files, drop []string) []string {
	seen := make(map[string]bool, len(drop))
	for _, f := range drop {
		seen[f] = true
	}
	return slices.DeleteFunc(files, func(f string) bool { return seen[f] })
}
