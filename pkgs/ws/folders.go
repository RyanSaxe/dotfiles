package main

import (
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

type place struct{ dir, session string }

// goPopup lists running sessions, then repositories by their last git
// activity, then bookmarks, each folder once.
func goPopup(b mux.Backend) popup.Popup {
	return popup.Popup{
		Noun: "folders",
		Tabs: []popup.Tab{{Name: "Folders", Empty: "No sessions, repositories or bookmarks."}},
		Load: func(int) ([]popup.Row, error) {
			ss, err := b.Sessions()
			// Asking what each session is doing takes a few Rex calls, so they
			// run while the walk does.
			doing := make([]mux.Pane, len(ss))
			var wg sync.WaitGroup
			for i, s := range ss {
				wg.Go(func() { doing[i] = b.Landing(s.ID) })
			}
			wts, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", "*"))
			dirs, marks := repos(), bookmarks()
			folder := map[string]string{} // a session's label to its folder
			for _, d := range slices.Concat(wts, marks, dirs) {
				folder[labelFor(d)] = d
			}
			type dated struct {
				dir string
				at  time.Time
			}
			ds := make([]dated, len(dirs))
			for i, d := range dirs {
				ds[i] = dated{d, activity(d)}
			}
			slices.SortStableFunc(ds, func(a, b dated) int { return b.at.Compare(a.at) })
			var rows []popup.Row
			listed := map[string]bool{}
			add := func(label string, r popup.Row) {
				if !listed[label] {
					listed[label] = true
					rows = append(rows, r)
				}
			}
			wg.Wait()
			for i, s := range ss {
				add(s.Label, popup.Row{ID: s.ID, Title: s.Label, Detail: tilde(cmp.Or(folder[s.Label], doing[i].Folder)), Tag: doingTag(doing[i].Doing), Data: place{folder[s.Label], s.ID}})
			}
			for _, d := range ds {
				add(labelFor(d.dir), popup.Row{ID: d.dir, Title: filepath.Base(d.dir), Detail: tilde(d.dir), Qualifier: relAge(d.at), Data: place{dir: d.dir}})
			}
			for _, d := range marks {
				add(labelFor(d), popup.Row{ID: d, Title: filepath.Base(d), Detail: tilde(d), Tag: popup.Dim.SetString("bookmark"), Data: place{dir: d}})
			}
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			p := r.Data.(place)
			if p.session == "" {
				return folderSummary(p.dir), nil
			}
			out, err := b.Capture(p.session)
			return popup.Tail(out), err
		},
		Actions: []popup.Action{
			{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
				p := r.Data.(place)
				return popup.Do(func() error {
					if p.session != "" {
						return b.Show(p.session)
					}
					return open(b, p.dir, start{}, true)
				}, popup.Quit)
			}},
			{Key: "ctrl+f", Help: "files", Run: func(r popup.Row) tea.Cmd {
				p := r.Data.(place)
				if p.dir == "" {
					return popup.Say(r.Title + " has no folder to search")
				}
				return popup.Push(filesPopup(b, p.dir))
			}},
			{Key: "ctrl+x", Help: "close", Run: func(r popup.Row) tea.Cmd {
				p := r.Data.(place)
				if p.session == "" {
					return popup.Say(r.Title + " has no session to close")
				}
				return popup.Do(func() error { return b.Kill(p.session) }, popup.Reload("closed "+r.Title))
			}},
		},
	}
}

// doingTag names what a session's pane is doing: an agent's status in its
// color, else the program it runs.
func doingTag(doing string) lipgloss.Style {
	if s, ok := mux.ParseStatus(doing); ok {
		return statusTag(s)
	}
	return popup.Dim.SetString(cmp.Or(doing, "open"))
}

// folderSummary is a folder's git status, the top two levels of its tree,
// then its recent commits. tree leaves out what git ignores and does not
// open a folder of more than 25 entries.
func folderSummary(dir string) string {
	summary := gitSummary(dir)
	tree, _ := runIn(dir, "tree", "-C", "-L", "2", "--dirsfirst", "--gitignore", "--filelimit", "25", "--noreport", "-I", ".git")
	if status, log, ok := strings.Cut(summary, "\n\n"); ok {
		return status + "\n\n" + tree + "\n\n" + log
	}
	return summary + "\n\n" + tree
}

// activity is when git last moved a folder's HEAD, by a commit, checkout or
// pull. It reads the time off git's log file, since asking git costs a
// process per folder.
func activity(dir string) time.Time {
	info, err := os.Stat(filepath.Join(dir, ".git", "logs", "HEAD"))
	if err != nil {
		return time.Time{}
	}
	return info.ModTime()
}

// repos finds git checkouts anywhere under the home folder. It stops at a
// repository, since nothing inside one is a separate project, and skips
// hidden folders, ~/Library, ~/worktrees, which Worktrees lists, and folders
// that hold no projects. That walk takes about 30 ms.
func repos() []string {
	skip := map[string]bool{"Library": true, filepath.Base(worktreeRoot): true, "node_modules": true,
		"Applications": true, "Movies": true, "Music": true, "Pictures": true}
	var found []string
	var walk func(string)
	walk = func(dir string) {
		entries, _ := os.ReadDir(dir)
		for _, e := range entries {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") || skip[e.Name()] {
				continue
			}
			p := filepath.Join(dir, e.Name())
			if _, err := os.Stat(filepath.Join(p, ".git")); err == nil {
				found = append(found, p)
			} else {
				walk(p)
			}
		}
	}
	walk(home)
	return found
}

func bookmarks() []string {
	data, _ := os.ReadFile(filepath.Join(home, ".config", "ws", "bookmarks"))
	var dirs []string
	for line := range strings.SplitSeq(string(data), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			if rest, ok := strings.CutPrefix(line, "~"); ok {
				line = home + rest
			}
			dirs = append(dirs, line)
		}
	}
	return dirs
}
