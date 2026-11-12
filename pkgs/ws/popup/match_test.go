package popup_test

import (
	"os/exec"
	"slices"
	"strings"
	"testing"

	"workspace/popup"
)

// Match promises fzf's order, so it's checked against the fzf command on the
// same lines.
func TestMatchOrdersLikeFzf(t *testing.T) {
	fzf, err := exec.LookPath("fzf")
	if err != nil {
		t.Skip("fzf is not installed")
	}
	lines := []string{
		"src/hub/server.mjs", "tests/hub/server.test.mjs", "src/frame/review/review.css",
		"src/frame/review/review.mjs", "src/frame/sync/hub-version.mjs", "adapters/codex/app-server.mjs",
		"README.md", "docs/Server.md", "scripts/serve.sh", "src/shared/settings.mjs",
	}
	for _, term := range []string{"srvr", "server", "Server", "rev", "md", "zzz"} {
		cmd := exec.Command(fzf, "--filter", term)
		cmd.Stdin = strings.NewReader(strings.Join(lines, "\n"))
		out, _ := cmd.Output() // fzf exits 1 when nothing matches
		var got []string
		for _, r := range popup.Match(term, lines) {
			got = append(got, lines[r.Index])
		}
		if want := strings.Fields(string(out)); !slices.Equal(got, want) {
			t.Errorf("%q: Match gives %v, fzf gives %v", term, got, want)
		}
	}
}
