package main

import (
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/kitty"
	"workspace/mux"
	"workspace/popup"
)

func pick(b mux.Backend, name string) error {
	term := b.Images()
	dir, _ := os.Getwd()
	popups := map[string]func() popup.Popup{
		"go":        func() popup.Popup { return goPopup(b, foldersTab) },
		"worktrees": func() popup.Popup { return goPopup(b, worktreesTab) },
		"sessions":  func() popup.Popup { return goPopup(b, sessionsTab) },
		"agents":    func() popup.Popup { return goPopup(b, agentsTab) },
		"inbox":     func() popup.Popup { return inboxPopup(b, term, false) },
		"reviews":   func() popup.Popup { return inboxPopup(b, term, false) },
		"tasks":     func() popup.Popup { return inboxPopup(b, term, true) },
		"theme":     func() popup.Popup { return themePopup(term) },
		"files":     func() popup.Popup { return filesPopup(b, dir) },
		"keys":      func() popup.Popup { return keysPopup(b) },
	}
	build, ok := popups[name]
	if !ok {
		return fmt.Errorf("no popup named %s, only go, worktrees, sessions, agents, inbox, reviews, tasks, theme, keys or files", name)
	}
	// The mascot's accent colors the popups, and only the popups.
	if hex := accentColor(); hex != "" {
		popup.Accent = lipgloss.NewStyle().Foreground(lipgloss.Color(hex))
	}
	// Rex starts a new pane, such as the float a popup opens in, at 80×24, and
	// gives it its real size once the app draws it.
	var placeholder tea.WindowSizeMsg
	if _, ok := b.(mux.Rex); ok {
		placeholder = tea.WindowSizeMsg{Width: 80, Height: 24}
	}
	// The mascot and its accent are drawn again on each reload, so the theme
	// popup shows a new mascot and its color as soon as it's set.
	return popup.Run(build(), func() popup.Art {
		art := mascotArt(2, term)
		art.Accent = accentColor()
		return art
	}, placeholder)
}

// perLoad shares work between the tabs of one load: the first tab to ask
// runs it, and the others wait for its result. A tab that asks again is in
// the next load, which runs the work afresh. The work can report what it has
// so far, and the tab that runs it gets those reports in progress, which may
// be nil.
func perLoad[T any](work func(report func(T)) (T, error)) func(tab int, progress func(T)) (T, error) {
	var (
		mu    sync.Mutex
		run   func(progress func(T)) (T, error)
		asked map[int]bool
	)
	return func(tab int, progress func(T)) (T, error) {
		mu.Lock()
		if run == nil || asked[tab] {
			run, asked = once(work), map[int]bool{}
		}
		asked[tab] = true
		this := run
		mu.Unlock()
		return this(progress)
	}
}

// once runs work for the first caller, with that caller's progress, and gives
// every caller its result.
func once[T any](work func(report func(T)) (T, error)) func(progress func(T)) (T, error) {
	var (
		do     sync.Once
		result T
		err    error
	)
	return func(progress func(T)) (T, error) {
		do.Do(func() {
			if progress == nil {
				progress = func(T) {}
			}
			result, err = work(progress)
		})
		return result, err
	}
}

// showTab runs args in a new tab of the place p and goes there, since the
// person who picked a row in a popup wants to see what it opened.
func showTab(b mux.Backend, p mux.Place, dir string, args ...string) error {
	t, err := b.Tab(p, dir, args...)
	if err != nil {
		return err
	}
	return b.Show(t)
}

// onTabs makes actions work only on the tabs listed, and there only where
// their own When says.
func onTabs(tabs []int, actions []popup.Action) []popup.Action {
	for i, a := range actions {
		actions[i].When = func(tab int, r popup.Row) bool {
			return slices.Contains(tabs, tab) && (a.When == nil || a.When(tab, r))
		}
	}
	return actions
}

// inboxPopup is what waits on you outside the terminal: Reviews' tabs, then
// the Tasks tabs. It opens on Needs you, or on the first Tasks tab when
// onTasks is set. Each half keeps its own tabs, rows and keys, numbered from
// 0, and a row's Data says which half it came from.
func inboxPopup(b mux.Backend, term kitty.Terminal, onTasks bool) popup.Popup {
	reviews, tasks := reviewTabs(b, term), taskTabs(b, term)
	n := len(reviews.Tabs)
	of := func(r popup.Row) popup.Popup {
		if _, ok := r.Data.(task); ok {
			return tasks
		}
		return reviews
	}
	p := popup.Popup{
		Noun: reviews.Noun,
		Tabs: slices.Concat(reviews.Tabs, tasks.Tabs),
		Load: func(tab int, show func([]popup.Row)) ([]popup.Row, error) {
			if tab < n {
				return reviews.Load(tab, show)
			}
			return tasks.Load(tab-n, show)
		},
		Fetch: func(r popup.Row) (any, error) { return of(r).Fetch(r) },
		Head: func(r popup.Row, d any, w int) []string {
			if head := of(r).Head; head != nil {
				return head(r, d, w)
			}
			return nil
		},
		Body:    func(r popup.Row, d any, w int) string { return of(r).Body(r, d, w) },
		Actions: slices.Concat(tabsFrom(0, n, reviews.Actions), tabsFrom(n, len(tasks.Tabs), tasks.Actions)),
	}
	if onTasks {
		p.Start = n
	}
	return p
}

// tabsFrom makes actions work only on the count tabs from first, which they
// know as tabs 0 and up, and there only where their own When says.
func tabsFrom(first, count int, actions []popup.Action) []popup.Action {
	for i, a := range actions {
		actions[i].When = func(tab int, r popup.Row) bool {
			return tab >= first && tab < first+count && (a.When == nil || a.When(tab-first, r))
		}
	}
	return actions
}

// page runs a pager such as delta in the popup's place, and comes back to
// the popup with its error, if any, as a notice.
func page(pager *exec.Cmd) tea.Cmd {
	return tea.ExecProcess(pager, func(err error) tea.Msg {
		if err != nil {
			return popup.Notice(err.Error())
		}
		return popup.Notice("")
	})
}

// statusTag names an agent's status in its color.
func statusTag(s mux.Status) lipgloss.Style {
	return map[mux.Status]lipgloss.Style{mux.Blocked: popup.Red, mux.Error: popup.Red, mux.Done: popup.Green,
		mux.Working: popup.Fg("5"), mux.Idle: popup.Dim, mux.Open: popup.Accent}[s].SetString(s.String())
}

// gitSummary is a folder's branch, changes and recent commits, in git's colors.
func gitSummary(dir string) string {
	if dir == "" {
		return ""
	}
	status, err := git(dir, "-c", "color.ui=always", "status", "--short", "--branch")
	if err != nil {
		return popup.Dim.Render("not a git repository")
	}
	log, _ := git(dir, "-c", "color.ui=always", "log", "--oneline", "--decorate", "-100")
	return status + "\n\n" + log
}

func tilde(p string) string {
	if p == home || strings.HasPrefix(p, home+"/") {
		return "~" + p[len(home):]
	}
	return p
}
