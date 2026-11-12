package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"workspace/mux"
	"workspace/popup"
)

func pick(b mux.Backend, name string) error {
	term := b.Images()
	dir, _ := os.Getwd()
	popups := map[string]func() popup.Popup{
		"go":        func() popup.Popup { return goPopup(b) },
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
		return fmt.Errorf("no popup named %s, only go, worktrees, reviews, tasks, agents, theme, keys or files", name)
	}
	// The mascot's accent colors the popups, and only the popups.
	if hex := accentColor(); hex != "" {
		popup.Accent = lipgloss.NewStyle().Foreground(lipgloss.Color(hex))
	}
	return popup.Run(build(), mascotArt(2, term))
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
