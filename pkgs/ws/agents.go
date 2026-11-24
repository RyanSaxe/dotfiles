package main

import (
	"cmp"
	"slices"
	"strings"
	"workspace/mux"
	"workspace/popup"
)

// agentRows are the go popup's Agents tab: each terminal that reports a
// program status, the latest report first.
func agentRows(s mux.Snapshot) []popup.Row {
	ps := s.Agents()
	slices.SortFunc(ps, func(a, b mux.Pane) int { return b.Updated.Compare(a.Updated) })
	rows := make([]popup.Row, len(ps))
	for i, p := range ps {
		app := p.App
		if app == "claude-code" {
			app = "" // nearly every agent is, so only the others say
		}
		detail := strings.Join(slices.DeleteFunc([]string{p.Label, tilde(p.Folder), app}, func(s string) bool { return s == "" }), " · ")
		rows[i] = popup.Row{ID: p.ID, Title: cmp.Or(p.Title, p.Label), Detail: detail, Qualifier: relAge(p.Updated), Tag: statusTag(p.Status), Data: p}
	}
	return rows
}
