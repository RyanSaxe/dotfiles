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

// A place is a folder, a session, or a folder and its session.
type place struct{ dir, session string }

// The go popup's tabs.
const (
	foldersTab = iota
	sessionsTab
)

// goPopup lists repositories, worktrees and bookmarks by their last git
// activity on one tab, and running sessions on the other. It opens on first,
// foldersTab or sessionsTab.
func goPopup(b mux.Backend, first int) popup.Popup {
	return popup.Popup{
		Noun:  "folders and sessions",
		Tabs:  []popup.Tab{foldersTab: {Name: "Folders", Empty: "No repositories, worktrees or bookmarks."}, sessionsTab: {Name: "Sessions", Empty: "No sessions are running."}},
		Start: first,
		Load: func(tab int) ([]popup.Row, error) {
			ss, err := b.Sessions()
			if tab == foldersTab {
				return folderRows(ss), err
			}
			return sessionRows(b, ss), err
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

// folderRows are the Folders tab: each folder, with its session when one is
// running, so Enter goes to that session.
func folderRows(ss []mux.Session) []popup.Row {
	sessions := map[string]string{} // a label to its session
	for _, s := range ss {
		sessions[s.Label] = s.ID
	}
	var rows []popup.Row
	for _, f := range folders() {
		r := popup.Row{ID: f.dir, Title: folderTitle(f.dir), Detail: tilde(f.dir), Qualifier: relAge(f.at), Data: place{f.dir, sessions[labelFor(f.dir)]}}
		if f.bookmark {
			r.Tag = popup.Dim.SetString("bookmark")
		}
		rows = append(rows, r)
	}
	return rows
}

// sessionRows are the Sessions tab: each running session with what it's
// doing, and its folder.
func sessionRows(b mux.Backend, ss []mux.Session) []popup.Row {
	// Asking what each session is doing takes a few Rex calls, so they run
	// while the walk does.
	doing := make([]mux.Pane, len(ss))
	var wg sync.WaitGroup
	for i, s := range ss {
		wg.Go(func() { doing[i] = b.Landing(s.ID) })
	}
	dirs := map[string]string{} // a session's label to its folder
	for _, f := range folders() {
		dirs[labelFor(f.dir)] = f.dir
	}
	wg.Wait()
	rows := make([]popup.Row, len(ss))
	for i, s := range ss {
		rows[i] = popup.Row{ID: s.ID, Title: s.Label, Detail: tilde(cmp.Or(dirs[s.Label], doing[i].Folder)), Tag: doingTag(doing[i].Doing), Data: place{dirs[s.Label], s.ID}}
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
