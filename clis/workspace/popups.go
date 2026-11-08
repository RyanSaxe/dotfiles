package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

func pick(name string) error {
	popups := map[string]func() popup{"go": goPopup, "worktrees": worktreesPopup, "reviews": reviewsPopup, "tasks": tasksPopup, "agents": agentsPopup}
	build, ok := popups[name]
	if !ok {
		return fmt.Errorf("no popup named %s, only go, worktrees, reviews, tasks or agents", name)
	}
	_, err := tea.NewProgram(newFrame(build()), tea.WithAltScreen()).Run()
	return err
}

type place struct{ dir, session string }

// goPopup lists running sessions, then repositories by their last commit,
// then bookmarks, each folder once.
func goPopup() popup {
	return popup{
		title: "Go", noun: "folders",
		tabs: []tab{{"Folders", "No sessions, repositories or bookmarks."}},
		load: func(int) ([]row, error) {
			ss, err := mux().sessions()
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
			var wg sync.WaitGroup
			for i, d := range dirs {
				wg.Go(func() { ds[i] = dated{d, commitTime(d)} })
			}
			wg.Wait()
			slices.SortStableFunc(ds, func(a, b dated) int { return b.at.Compare(a.at) })
			var rows []row
			listed := map[string]bool{}
			add := func(label string, r row) {
				if !listed[label] {
					listed[label] = true
					rows = append(rows, r)
				}
			}
			for _, s := range ss {
				add(s.label, row{id: s.id, title: s.label, meta: tilde(folder[s.label]), tag: stateTag("open"), data: place{folder[s.label], s.id}})
			}
			for _, d := range ds {
				add(labelFor(d.dir), row{id: d.dir, title: filepath.Base(d.dir), meta: tilde(d.dir), side: relAge(d.at), data: place{dir: d.dir}})
			}
			for _, d := range marks {
				add(labelFor(d), row{id: d, title: filepath.Base(d), meta: tilde(d), tag: dim.SetString("bookmark"), data: place{dir: d}})
			}
			return rows, err
		},
		fetch: func(r row) (any, error) { return gitSummary(r.data.(place).dir), nil },
		actions: []action{
			{key: "enter", help: "go", run: func(r row) tea.Cmd {
				p := r.data.(place)
				return act(func() error {
					if p.session != "" {
						return mux().show(p.session)
					}
					return open(p.dir, "agent", "claude", "", true)
				}, quitMsg{})
			}},
			{key: "ctrl+x", help: "close", run: func(r row) tea.Cmd {
				p := r.data.(place)
				if p.session == "" {
					return status(r.title + " has no session to close")
				}
				return act(func() error { return mux().kill(p.session) }, reloadMsg("closed "+r.title))
			}},
		},
	}
}

func worktreesPopup() popup {
	return popup{
		title: "Worktrees", noun: "worktrees",
		tabs: []tab{{"All", "No worktrees under ~/worktrees."}},
		load: func(int) ([]row, error) {
			var rows []row
			for _, w := range worktrees() {
				meta := w.Project + " · " + w.Branch
				if w.Dirty {
					meta += " · modified"
				}
				rows = append(rows, row{id: w.Path, title: w.Name, meta: meta, side: relAge(w.Updated), tag: stateTag(w.State), data: w})
			}
			return rows, nil
		},
		fetch: func(r row) (any, error) { return gitSummary(r.data.(worktree).Path), nil },
		actions: []action{
			{key: "enter", help: "go", run: func(r row) tea.Cmd {
				w := r.data.(worktree)
				return act(func() error { return open(w.Path, "agent", "claude", "", true) }, quitMsg{})
			}},
			{key: "ctrl+n", help: "new", always: true, run: func(r row) tea.Cmd {
				from := "." // with no worktrees yet, the project is the folder ws runs in
				if w, ok := r.data.(worktree); ok {
					from = w.Path
				}
				return ask("name:", func(name string) tea.Cmd {
					return ask("agent (claude or codex):", func(agent string) tea.Cmd {
						return ask("prompt:", func(prompt string) tea.Cmd {
							return tea.Batch(status("making "+name+"…"), act(func() error {
								main, err := mainCheckout(from)
								if err != nil {
									return err
								}
								return newWorktree(main, name, cmp.Or(agent, "claude"), prompt, "agent", "")
							}, quitMsg{}))
						})
					})
				})
			}},
			{key: "ctrl+x", help: "remove", run: func(r row) tea.Cmd {
				w := r.data.(worktree)
				rm := func(force bool) tea.Cmd {
					return func() tea.Msg {
						if err := remove(w.Project+"/"+w.Name, force); err != nil {
							return reloadMsg(err.Error())
						}
						return reloadMsg("removed " + w.Project + "/" + w.Name)
					}
				}
				if !w.Dirty {
					return rm(false)
				}
				return ask(w.Name+" has uncommitted changes. Remove it and its branch anyway? (y/N)", func(answer string) tea.Cmd {
					if strings.EqualFold(answer, "y") {
						return rm(true)
					}
					return nil
				})
			}},
		},
	}
}

func agentsPopup() popup {
	return popup{
		title: "Agents", noun: "terminals", follow: true,
		tabs: []tab{{"Terminals", "No terminal reports a program status."}},
		load: func(int) ([]row, error) {
			if !inRex {
				return nil, errors.New("agents lists Rex terminals, and this terminal is not in Rex")
			}
			ts, err := rexTerminals()
			ts = slices.DeleteFunc(ts, func(t terminal) bool { return t.state == "" })
			slices.SortFunc(ts, func(a, b terminal) int { return cmp.Or(rank(a.state)-rank(b.state), b.updated.Compare(a.updated)) })
			rows := make([]row, len(ts))
			for i, t := range ts {
				meta := strings.Join(slices.DeleteFunc([]string{t.app, tilde(t.cwd)}, func(s string) bool { return s == "" }), " · ")
				rows[i] = row{id: t.block, title: t.label, meta: meta, side: relAge(t.updated), tag: stateTag(t.state), data: t}
			}
			return rows, err
		},
		fetch: func(r row) (any, error) {
			t := r.data.(terminal)
			out, err := rex("capture", "-s", t.session, "-b", t.block, "--trim")
			lines := strings.Split(out, "\n")
			return strings.Join(lines[max(0, len(lines)-40):], "\n"), err
		},
		actions: []action{{key: "enter", help: "go", run: func(r row) tea.Cmd {
			t := r.data.(terminal)
			return act(func() error {
				err := rexMux{}.show(t.session)
				if err == nil {
					_, err = rex("focus", "-s", t.session, t.block)
				}
				return err
			}, quitMsg{})
		}}},
	}
}

// A task as `vault tasks --json` reports it. The vault CLI owns the task
// grammar and every write to a note, so ws reads and ticks tasks through it.
type task struct {
	ID, Text, Due, State, File string
	Line                       int
	Done                       bool
}

func openTasks() ([]task, error) {
	out, err := runIn("", "vault", "tasks", "--json")
	var ts []task
	if err == nil {
		err = json.Unmarshal([]byte(out), &ts)
	}
	return slices.DeleteFunc(ts, func(t task) bool { return t.Done }), err
}

func tasksPopup() popup {
	// The vault CLI has no default of its own, and this is the dotfiles' default.
	vault := cmp.Or(os.Getenv("VAULT_DIR"), filepath.Join(home, "generic", "vault"))
	os.Setenv("VAULT_DIR", vault)
	tags := map[string]lipgloss.Style{"overdue": red.SetString("overdue"), "today": yellow.SetString("today"),
		"tomorrow": accent.SetString("soon"), "near": accent.SetString("soon")}
	return popup{
		title: "Tasks", noun: "tasks",
		tabs: []tab{{"Open", "No open tasks."}},
		load: func(int) ([]row, error) {
			ts, err := openTasks()
			// ISO dates sort as text, and undated tasks go last.
			slices.SortStableFunc(ts, func(a, b task) int { return strings.Compare(cmp.Or(a.Due, "~"), cmp.Or(b.Due, "~")) })
			rows := make([]row, len(ts))
			for i, t := range ts {
				rows[i] = row{id: t.ID, title: t.Text, meta: t.ID, tag: tags[t.State], data: t}
				if due, err := time.Parse(time.DateOnly, t.Due); err == nil {
					rows[i].side = due.Format("Jan 2")
				}
			}
			return rows, err
		},
		fetch: func(r row) (any, error) {
			t := r.data.(task)
			data, err := os.ReadFile(filepath.Join(vault, t.File))
			lines := strings.Split(string(data), "\n")
			if t.Line > len(lines) {
				return "", err
			}
			lines[t.Line-1] = accent.Render(lines[t.Line-1])
			return strings.Join(lines[max(0, t.Line-6):min(len(lines), t.Line+15)], "\n"), err
		},
		actions: []action{
			{key: "enter", help: "edit", run: func(r row) tea.Cmd {
				t := r.data.(task)
				line := "+" + strconv.Itoa(t.Line)
				if !inRex {
					return tea.ExecProcess(exec.Command("nvim", line, filepath.Join(vault, t.File)), func(err error) tea.Msg {
						if err != nil {
							return statusMsg(err.Error())
						}
						return reloadMsg("")
					})
				}
				return act(func() error {
					_, err := rex("run", "-s", os.Getenv("REX_SESSION"), "-c", vault, "--", "nvim", line, t.File)
					return err
				}, quitMsg{})
			}},
			{key: "ctrl+x", help: "done", run: func(r row) tea.Cmd {
				t := r.data.(task)
				return act(func() error {
					// Ids are file:line, so a note edited since the list loaded
					// can put another task at this id.
					ts, err := openTasks()
					if i := slices.IndexFunc(ts, func(c task) bool { return c.ID == t.ID }); err == nil && (i < 0 || ts[i].Text != t.Text) {
						err = fmt.Errorf("%s changed since the list loaded, so press r to refresh", t.ID)
					}
					if err == nil {
						_, err = runIn("", "vault", "task", "done", t.ID)
					}
					return err
				}, reloadMsg("done: "+t.Text))
			}},
		},
	}
}

// gitSummary is a folder's branch, changes and recent commits, in git's colors.
func gitSummary(dir string) string {
	if dir == "" {
		return ""
	}
	status, err := git(dir, "-c", "color.ui=always", "status", "--short", "--branch")
	if err != nil {
		return dim.Render("not a git repository")
	}
	log, _ := git(dir, "-c", "color.ui=always", "log", "--oneline", "--decorate", "-30")
	return status + "\n\n" + log
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

func tilde(p string) string {
	if p == home || strings.HasPrefix(p, home+"/") {
		return "~" + p[len(home):]
	}
	return p
}
