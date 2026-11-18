package main

import (
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

// A place is a folder, a place it's open in, or both, with the pane going
// to the place lands on.
type place struct {
	dir  string
	at   mux.Place // Session is "" while the folder isn't open
	pane mux.Pane
}

// The go popup's tabs.
const (
	foldersTab = iota
	sessionsTab
)

// goPopup lists repositories, worktrees and bookmarks by their last git
// activity on one tab, and the places folders are open in, each session and
// named tab, on the other. It opens on first, foldersTab or sessionsTab.
func goPopup(b mux.Backend, first int) popup.Popup {
	walk := perLoad(func() ([]folder, error) { return folders(), nil })
	snapshot := perLoad(func() (mux.Snapshot, error) { return b.Snapshot() })
	return popup.Popup{
		Noun:  "folders and sessions",
		Tabs:  []popup.Tab{foldersTab: {Name: "Folders", Empty: "No repositories, worktrees or bookmarks."}, sessionsTab: {Name: "Sessions", Empty: "No sessions are running."}},
		Start: first,
		// Folders shows the walk's rows at once, and tags the folders that
		// are open once the snapshot comes. Enter on an untagged row still
		// goes to its place, since open finds it. Sessions reads the snapshot
		// first, so it runs while Folders walks.
		Load: func(tab int, show func([]popup.Row)) ([]popup.Row, error) {
			if tab == sessionsTab {
				s, err := snapshot(tab)
				fs, _ := walk(tab)
				return sessionRows(fs, s), err
			}
			fs, _ := walk(tab)
			show(folderRows(fs, mux.Snapshot{}))
			s, err := snapshot(tab)
			return folderRows(fs, s), err
		},
		Fetch: func(r popup.Row) (any, error) {
			// A place's pane shows what it's doing, and a folder without one
			// shows its summary.
			switch p := r.Data.(place); {
			case p.pane.ID != "":
				out, err := b.Capture(p.pane)
				return popup.Tail(out), err
			case p.dir != "":
				return folderSummary(p.dir), nil
			}
			return nil, nil
		},
		Actions: []popup.Action{
			{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
				p := r.Data.(place)
				return popup.Do(func() error {
					if p.at.Session != "" {
						return b.Show(p.at)
					}
					return open(b, p.dir, start{}, true)
				}, popup.Quit)
			}},
			// A folder's row knows its place once the snapshot comes.
			{Key: "ctrl+x", Help: "close", When: func(_ int, r popup.Row) bool { return r.Data.(place).at.Session != "" }, Run: func(r popup.Row) tea.Cmd {
				at := r.Data.(place).at
				return popup.Ask("Close "+r.Title+" and everything running in it? (y/N)", func(answer string) tea.Cmd {
					if !strings.EqualFold(answer, "y") {
						return nil
					}
					return popup.Do(func() error { return b.Kill(at) }, popup.Reload("closed "+r.Title))
				})
			}},
			{Key: "ctrl+f", Help: "files", When: func(_ int, r popup.Row) bool { return r.Data.(place).dir != "" }, Run: func(r popup.Row) tea.Cmd {
				return popup.Push(filesPopup(b, r.Data.(place).dir))
			}},
		},
	}
}

// A folder is a repository, a worktree or a bookmark.
type folder struct {
	dir      string
	at       time.Time // when git last moved its HEAD
	bookmark bool
}

// folders lists repositories, worktrees and bookmarks, each once, the latest
// git activity first.
func folders() []folder {
	wts, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", "*", ".git"))
	for i, w := range wts {
		wts[i] = filepath.Dir(w)
	}
	marks := bookmarks()
	var fs []folder
	listed := map[string]bool{}
	for _, d := range slices.Concat(repos(), wts, marks) {
		if !listed[d] {
			listed[d] = true
			fs = append(fs, folder{d, activity(d), slices.Contains(marks, d)})
		}
	}
	slices.SortStableFunc(fs, func(a, b folder) int { return b.at.Compare(a.at) })
	return fs
}

// folderRows are the Folders tab: each folder, with its place when it is
// open in s, so Enter goes to that place. The tag says whether that place is
// a session or a tab.
func folderRows(fs []folder, s mux.Snapshot) []popup.Row {
	places := map[string]mux.Place{} // a label to the first place with it
	for _, p := range s.Places() {
		if _, ok := places[p.Label]; !ok {
			places[p.Label] = p
		}
	}
	var rows []popup.Row
	for _, f := range fs {
		at, open := places[labelFor(f.dir)]
		pane, _ := s.Landing(at)
		r := popup.Row{ID: f.dir, Title: folderTitle(f.dir), Detail: tilde(f.dir), Qualifier: relAge(f.at), Data: place{f.dir, at, pane}}
		switch {
		case open && at.Named:
			r.Tag = popup.Green.SetString("tab")
		case open:
			r.Tag = popup.Green.SetString("session")
		case f.bookmark:
			r.Tag = popup.Dim.SetString("bookmark")
		}
		rows = append(rows, r)
	}
	return rows
}

// sessionRows are the Sessions tab: each place, a session or a named tab,
// with what it's doing, and its folder.
func sessionRows(fs []folder, s mux.Snapshot) []popup.Row {
	dirs := map[string]string{} // a place's label to its folder
	for _, f := range fs {
		dirs[labelFor(f.dir)] = f.dir
	}
	places := s.Places()
	rows := make([]popup.Row, len(places))
	for i, at := range places {
		dir, tag := dirs[at.Label], popup.Dim.SetString("open")
		pane, ok := s.Landing(at)
		if ok {
			tag = doingTag(pane)
		}
		rows[i] = popup.Row{ID: at.Session + " " + at.Tab, Title: at.Label, Detail: tilde(cmp.Or(dir, pane.Folder)), Tag: tag, Data: place{dir, at, pane}}
	}
	return rows
}

// folderTitle is PROJECT/NAME for a worktree and the folder's name otherwise.
func folderTitle(dir string) string {
	if rel, err := filepath.Rel(worktreeRoot, dir); err == nil && !strings.HasPrefix(rel, "..") && strings.Count(rel, "/") == 1 {
		return rel
	}
	return filepath.Base(dir)
}

// doingTag names what a pane is doing: its agent's status in its color,
// else the program it runs.
func doingTag(p mux.Pane) lipgloss.Style {
	if p.Status != mux.Open {
		return statusTag(p.Status)
	}
	return popup.Dim.SetString(cmp.Or(p.Program, "open"))
}

// folderSummary is a folder's git status, the top two levels of its tree,
// then its recent commits. tree leaves out what git ignores and does not
// open a folder of more than 25 entries.
func folderSummary(dir string) string {
	summary := gitSummary(dir)
	args := []string{"-C", "--dirsfirst", "--gitignore", "--noreport", "-I", ".git"}
	tree, _ := runIn(dir, "tree", append(args, "-L", "2", "--filelimit", "25")...)
	// The limit holds for the top folder too, and then tree prints only its
	// name, so a top folder over the limit is listed one level deep instead.
	if !strings.Contains(tree, "\n") {
		tree, _ = runIn(dir, "tree", append(args, "-L", "1")...)
	}
	if status, log, ok := strings.Cut(summary, "\n\n"); ok {
		return status + "\n\n" + tree + "\n\n" + log
	}
	return summary + "\n\n" + tree
}

// activity is when git last moved a folder's HEAD, by a commit, checkout or
// pull. It reads the time off git's log file, since asking git costs a
// process per folder.
func activity(dir string) time.Time {
	gitDir := filepath.Join(dir, ".git")
	// A worktree's .git is a file naming its folder in the main checkout's.
	if data, err := os.ReadFile(gitDir); err == nil {
		if named, ok := strings.CutPrefix(strings.TrimSpace(string(data)), "gitdir: "); ok {
			gitDir = named
			if !filepath.IsAbs(named) {
				gitDir = filepath.Join(dir, named)
			}
		}
	}
	info, err := os.Stat(filepath.Join(gitDir, "logs", "HEAD"))
	if err != nil {
		return time.Time{}
	}
	return info.ModTime()
}

// repos finds git checkouts anywhere under the home folder. It stops at a
// repository, since nothing inside one is a separate project, and skips
// hidden folders, ~/Library, ~/worktrees, which Worktrees lists, and folders
// that hold no projects. That walk takes about 7 ms. Go's module cache in
// ~/go would add about 140 ms, so GOPATH keeps it in ~/.local/share/go.
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
	data, _ := os.ReadFile(filepath.Join(configDir, "bookmarks"))
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
