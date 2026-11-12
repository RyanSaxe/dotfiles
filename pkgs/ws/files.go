package main

import (
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

// filesPopup lists dir's files as fd finds them. Each tab lets more in:
// hidden files, then what git ignores as well.
func filesPopup(b mux.Backend, dir string) popup.Popup {
	flags := [][]string{nil, {"--hidden"}, {"--hidden", "--no-ignore"}}
	return popup.Popup{
		Noun: "files", OneLine: true,
		Tabs: []popup.Tab{{Name: "Files", Empty: "No files."}, {Name: "+ hidden", Empty: "No files."}, {Name: "+ ignored", Empty: "No files."}},
		Load: func(t int) ([]popup.Row, error) {
			out, err := runIn(dir, "fd", append([]string{"--type", "f", "--strip-cwd-prefix", "--exclude", ".git"}, flags[t]...)...)
			changed := gitChanges(dir)
			var rows []popup.Row
			for f := range strings.SplitSeq(out, "\n") {
				if f == "" {
					continue
				}
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
