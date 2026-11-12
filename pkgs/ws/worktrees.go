package main

import (
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"workspace/mux"
	"workspace/popup"
)

// worktreesPopup opens on the worktrees of the project ws runs in, with
// every project's on a second tab.
func worktreesPopup(b mux.Backend) popup.Popup {
	project := ""
	if main, err := mainCheckout("."); err == nil {
		project = filepath.Base(main)
	}
	tabs := []popup.Tab{{Name: "Worktrees", Empty: "No worktrees under ~/worktrees."}}
	if project != "" {
		tabs = []popup.Tab{{Name: project, Empty: "No worktrees of " + project + "."}, {Name: "All", Empty: "No worktrees under ~/worktrees."}}
	}
	return popup.Popup{
		Noun: "worktrees",
		Tabs: tabs,
		Load: func(t int) ([]popup.Row, error) {
			var rows []popup.Row
			for _, w := range worktrees(b) {
				if project != "" && t == 0 && w.Project != project {
					continue
				}
				// Only what the tab and the name don't already say: the project on
				// All, the branch where it isn't named after the worktree, and
				// whether it has changes, then the last commit, so the line is
				// never empty.
				var parts []string
				if project == "" || t != 0 {
					parts = append(parts, w.Project)
				}
				if w.Branch != w.Name {
					parts = append(parts, w.Branch)
				}
				if w.Dirty {
					parts = append(parts, "modified")
				}
				meta := strings.Join(append(parts, w.Subject), " · ")
				r := popup.Row{ID: w.Path, Title: w.Name, Detail: meta, Qualifier: relAge(w.Updated), Data: w}
				if s, ok := mux.ParseStatus(w.State); ok {
					r.Tag = statusTag(s)
				}
				rows = append(rows, r)
			}
			return rows, nil
		},
		Fetch: func(r popup.Row) (any, error) { return gitSummary(r.Data.(worktree).Path), nil },
		Actions: []popup.Action{
			{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
				w := r.Data.(worktree)
				return popup.Do(func() error { return open(b, w.Path, start{}, true) }, popup.Quit)
			}},
			{Key: "ctrl+t", Help: "new", Always: true, Run: func(r popup.Row) tea.Cmd {
				from := "." // with no worktrees yet, the project is the folder ws runs in
				if w, ok := r.Data.(worktree); ok {
					from = w.Path
				}
				return popup.Ask("name:", func(name string) tea.Cmd {
					return popup.Ask("agent (claude or codex, or empty for "+defaultAgent()+"):", func(agent string) tea.Cmd {
						return popup.Ask("prompt:", func(prompt string) tea.Cmd {
							return tea.Batch(popup.Say("making "+name+"…"), popup.Do(func() error {
								main, err := mainCheckout(from)
								if err != nil {
									return err
								}
								return newWorktree(b, main, name, agent, prompt, "agent", "")
							}, popup.Quit))
						})
					})
				})
			}},
			{Key: "ctrl+x", Help: "remove", Run: func(r popup.Row) tea.Cmd {
				w := r.Data.(worktree)
				rm := func(force bool) tea.Cmd {
					return func() tea.Msg {
						if err := remove(b, w.Project+"/"+w.Name, force); err != nil {
							return popup.Reload(err.Error())
						}
						return popup.Reload("removed " + w.Project + "/" + w.Name)
					}
				}
				if !w.Dirty {
					return rm(false)
				}
				return popup.Ask(w.Name+" has uncommitted changes. Remove it and its branch anyway? (y/N)", func(answer string) tea.Cmd {
					if strings.EqualFold(answer, "y") {
						return rm(true)
					}
					return nil
				})
			}},
		},
	}
}
