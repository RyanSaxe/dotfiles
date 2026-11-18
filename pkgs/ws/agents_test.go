package main

import (
	"slices"
	"testing"

	"workspace/mux"
)

// The agents popup lists the latest status report first, whatever the
// status, and leaves out terminals that report none.
func TestTheAgentsPopupListsTheLatestReportFirst(t *testing.T) {
	onPath(t, "rex", `cat >/dev/null
echo '{"sessions": {}, "panes": [
  {"id": "blocked", "status": "blocked", "updated": "2026-11-17T09:00:00Z"},
  {"id": "working", "status": "working", "updated": "2026-11-17T11:00:00Z"},
  {"id": "plain"},
  {"id": "done", "status": "done", "updated": "2026-11-17T10:00:00Z"}
]}'`)
	rows, err := agentsPopup(mux.Rex{}).Load(0, nil)
	if err != nil {
		t.Fatal(err)
	}
	var listed []string
	for _, r := range rows {
		listed = append(listed, r.ID)
	}
	if want := []string{"working", "done", "blocked"}; !slices.Equal(listed, want) {
		t.Errorf("the agents popup lists %v, want %v", listed, want)
	}
}
