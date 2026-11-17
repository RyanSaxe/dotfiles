package main

import (
	"cmp"
	"errors"
	"slices"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"workspace/mux"
	"workspace/popup"
)

func agentsPopup(b mux.Backend) popup.Popup {
	_, inRex := b.(mux.Rex)
	return popup.Popup{
		Noun: "terminals",
		Tabs: []popup.Tab{{Name: "Agents", Empty: "No terminal reports a program status."}},
		Load: func(int, func([]popup.Row)) ([]popup.Row, error) {
			if !inRex {
				return nil, errors.New("agents lists Rex terminals, and this terminal is not in Rex")
			}
			s, err := b.Snapshot()
			ps := s.Agents()
			slices.SortFunc(ps, func(a, b mux.Pane) int { return cmp.Or(int(a.Status)-int(b.Status), b.Updated.Compare(a.Updated)) })
			rows := make([]popup.Row, len(ps))
			for i, p := range ps {
				app := p.App
				if app == "claude-code" {
					app = "" // nearly every agent is, so only the others say
				}
				detail := strings.Join(slices.DeleteFunc([]string{p.Label, tilde(p.Folder), app}, func(s string) bool { return s == "" }), " · ")
				rows[i] = popup.Row{ID: p.ID, Title: cmp.Or(p.Title, p.Label), Detail: detail, Qualifier: relAge(p.Updated), Tag: statusTag(p.Status), Data: p}
			}
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			out, err := b.Capture(r.Data.(mux.Pane))
			return popup.Tail(out), err
		},
		Actions: []popup.Action{{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
			p := r.Data.(mux.Pane)
			return popup.Do(func() error {
				err := b.Show(p.Session)
				if err == nil {
					err = b.Focus(p)
				}
				return err
			}, popup.Quit)
		}}},
	}
}
