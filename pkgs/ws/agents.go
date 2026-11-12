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
	rex, inRex := b.(mux.Rex)
	return popup.Popup{
		Noun: "terminals",
		Tabs: []popup.Tab{{Name: "Agents", Empty: "No terminal reports a program status."}},
		Load: func(int) ([]popup.Row, error) {
			if !inRex {
				return nil, errors.New("agents lists Rex terminals, and this terminal is not in Rex")
			}
			ts, err := rex.Terminals()
			ts = slices.DeleteFunc(ts, func(t mux.Terminal) bool { return t.Status == mux.Open })
			slices.SortFunc(ts, func(a, b mux.Terminal) int { return cmp.Or(int(a.Status)-int(b.Status), b.Updated.Compare(a.Updated)) })
			rows := make([]popup.Row, len(ts))
			for i, t := range ts {
				app := t.App
				if app == "claude-code" {
					app = "" // nearly every agent is, so only the others say
				}
				detail := strings.Join(slices.DeleteFunc([]string{t.Label, tilde(t.Cwd), app}, func(s string) bool { return s == "" }), " · ")
				rows[i] = popup.Row{ID: t.Block, Title: cmp.Or(t.Title, t.Label), Detail: detail, Qualifier: relAge(t.Updated), Tag: statusTag(t.Status), Data: t}
			}
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			t := r.Data.(mux.Terminal)
			out, err := rex.CaptureBlock(t.Session, t.Block)
			return popup.Tail(out), err
		},
		Actions: []popup.Action{{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
			t := r.Data.(mux.Terminal)
			return popup.Do(func() error {
				err := rex.Show(t.Session)
				if err == nil {
					err = rex.Focus(t.Session, t.Block)
				}
				return err
			}, popup.Quit)
		}}},
	}
}
