package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

func pick(b mux.Backend, name string) error {
	term := b.Images()
	dir, _ := os.Getwd()
	popups := map[string]func() popup.Popup{
		"go":        func() popup.Popup { return goPopup(b, foldersTab) },
		"sessions":  func() popup.Popup { return goPopup(b, sessionsTab) },
		"worktrees": func() popup.Popup { return worktreesPopup(b) },
		"reviews":   func() popup.Popup { return reviewsPopup(b, term) },
		"tasks":     func() popup.Popup { return tasksPopup(b, term) },
		"agents":    func() popup.Popup { return agentsPopup(b) },
		"theme":     func() popup.Popup { return themePopup(term) },
		"files":     func() popup.Popup { return filesPopup(b, dir) },
		"keys":      func() popup.Popup { return keysPopup(b) },
	}
	build, ok := popups[name]
	if !ok {
		return fmt.Errorf("no popup named %s, only go, sessions, worktrees, reviews, tasks, agents, theme, keys or files", name)
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

// perLoad shares work between the tabs of one load, which all start at
// once: the first tab to ask runs it, and the others wait for its result. A
// tab that asks again is in the next load, which runs the work afresh.
func perLoad[T any](work func() (T, error)) func(tab int) (T, error) {
	var (
		mu    sync.Mutex
		run   func() (T, error)
		asked map[int]bool
	)
	return func(tab int) (T, error) {
		mu.Lock()
		if run == nil || asked[tab] {
			run, asked = sync.OnceValues(work), map[int]bool{}
		}
		asked[tab] = true
		this := run
		mu.Unlock()
		return this()
	}
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
