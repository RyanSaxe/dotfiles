package main

import (
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

// badges names and colors the values gh reports for reviews, merges and checks.
var badges = map[string]lipgloss.Style{
	"APPROVED": green.SetString("approved"), "REVIEW_REQUIRED": yellow.SetString("review required"),
	"CHANGES_REQUESTED": red.SetString("changes requested"), "CONFLICTING": red.SetString("conflicts"),
	"MERGEABLE": dim.SetString("mergeable"), "pass": green.SetString("passed"), "fail": red.SetString("failed"),
	"pending": yellow.SetString("pending"), "cancel": dim.SetString("cancelled"), "skipping": dim.SetString("skipped"),
}

// Field names match gh's JSON keys, which encoding/json matches case-insensitively.
type pr struct {
	Number     int
	Title, URL string
	IsDraft    bool
	UpdatedAt  time.Time
	Author     struct{ Login string }
	Repository struct{ Name, NameWithOwner string }
}

type prDetail struct {
	Body, ReviewDecision, Mergeable, HeadRefName, BaseRefName string
	Additions, Deletions, ChangedFiles                        int
	checks                                                    []struct{ Name, Bucket string }
	checksErr                                                 error
}

func reviewsPopup() popup {
	filters := []string{"--review-requested=@me", "--author=@me"}
	return popup{
		title: "Reviews", noun: "pull requests",
		tabs: []tab{{"Inbox", "Nothing is waiting on your review."}, {"Mine", "You have no open pull requests."}},
		load: func(t int) ([]row, error) {
			out, err := runIn("", "gh", "search", "prs", filters[t], "--state=open", "--sort=updated", "--limit=50",
				"--json=number,title,repository,author,updatedAt,url,isDraft")
			var prs []pr
			if err == nil {
				err = json.Unmarshal([]byte(out), &prs)
			}
			rows := make([]row, len(prs))
			for i, p := range prs {
				meta := p.Repository.Name
				if t == 0 {
					meta += " · " + p.Author.Login
				}
				rows[i] = row{id: p.Repository.NameWithOwner + "#" + strconv.Itoa(p.Number), prefix: "#" + strconv.Itoa(p.Number),
					title: p.Title, side: relAge(p.UpdatedAt), meta: meta, data: p}
				if p.IsDraft {
					rows[i].tag = yellow.SetString("draft")
				}
			}
			return rows, err
		},
		fetch: func(r row) (any, error) { return fetchPR(r.data.(pr)) },
		head:  prHead,
		body:  func(_ row, d any, w int) string { return renderBody(d.(*prDetail).Body, w) },
		actions: []action{
			{key: "enter", help: "open", run: func(r row) tea.Cmd {
				p := r.data.(pr)
				return act(func() error {
					_, err := runIn("", "gh", "pr", "view", strconv.Itoa(p.Number), "-R", p.Repository.NameWithOwner, "--web")
					return err
				}, statusMsg("opened "+p.URL))
			}},
			{key: "w", help: "worktree", run: func(r row) tea.Cmd {
				p := r.data.(pr)
				return tea.Batch(status("opening a worktree for "+r.id+"…"), act(func() error {
					dir := checkoutOf(p.Repository.NameWithOwner)
					if dir == "" {
						return fmt.Errorf("no local checkout of %s under the project folders", p.Repository.NameWithOwner)
					}
					return pullRequest(dir, strconv.Itoa(p.Number))
				}, quitMsg{}))
			}},
		},
	}
}

func fetchPR(p pr) (*prDetail, error) {
	num, repo, d := strconv.Itoa(p.Number), p.Repository.NameWithOwner, &prDetail{}
	var checksOut string
	done := make(chan struct{})
	go func() {
		checksOut, d.checksErr = runIn("", "gh", "pr", "checks", num, "-R", repo, "--json=name,state,bucket")
		close(done)
	}()
	out, err := runIn("", "gh", "pr", "view", num, "-R", repo,
		"--json=title,body,additions,deletions,changedFiles,reviewDecision,mergeable,headRefName,baseRefName")
	<-done
	if err == nil {
		err = json.Unmarshal([]byte(out), d)
	}
	// gh pr checks exits non-zero while checks fail or are pending but still
	// prints them. With no checks at all it prints nothing and says so.
	if checksOut != "" {
		d.checksErr = json.Unmarshal([]byte(checksOut), &d.checks)
	} else if d.checksErr != nil && strings.Contains(d.checksErr.Error(), "no checks reported") {
		d.checksErr = nil
	}
	return d, err
}

// checkoutOf finds a local clone with a remote on the GitHub repository owner/name.
func checkoutOf(nameWithOwner string) string {
	want := strings.ToLower(nameWithOwner)
	for _, dir := range repos() {
		remotes, _ := git(dir, "remote", "-v")
		for line := range strings.SplitSeq(remotes, "\n") {
			if f := strings.Fields(line); len(f) > 1 {
				url := strings.ToLower(strings.TrimSuffix(f[1], ".git"))
				if strings.HasSuffix(url, "/"+want) || strings.HasSuffix(url, ":"+want) {
					return dir
				}
			}
		}
	}
	return ""
}

func relAge(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	day, age := 24*time.Hour, time.Since(t)
	units := []time.Duration{365 * day, 30 * day, 7 * day, day, time.Hour, time.Minute}
	for i, name := range []string{"y", "mo", "w", "d", "h", "m"} {
		if age >= units[i] {
			return fmt.Sprintf("%d%s", age/units[i], name)
		}
	}
	return "now"
}

var htmlComment, blankRuns = regexp.MustCompile(`(?s)<!--.*?-->`), regexp.MustCompile(`\n{3,}`)

func renderBody(md string, w int) string {
	md = strings.TrimSpace(blankRuns.ReplaceAllString(htmlComment.ReplaceAllString(strings.ReplaceAll(md, "\r", ""), ""), "\n\n"))
	lines := strings.Split(md, "\n")
	for i, line := range lines {
		st := lipgloss.NewStyle()
		if strings.HasPrefix(line, "#") {
			line, st = strings.TrimLeft(line, "# "), bold
		}
		lines[i] = st.Width(w).Render(line)
	}
	return strings.Join(lines, "\n")
}

func prHead(r row, data any, w int) []string {
	p := r.data.(pr)
	meta := dim.Render(fmt.Sprintf("%s #%d · %s · %s ago", p.Repository.NameWithOwner, p.Number, p.Author.Login, relAge(p.UpdatedAt)))
	if p.IsDraft {
		meta += yellow.Render("  draft")
	}
	lines := []string{ansi.Truncate(meta, w, "…"), bold.Width(w).Render(p.Title), ""}
	d, ok := data.(*prDetail)
	if !ok {
		return lines
	}
	add := func(label, value string) {
		lines = append(lines, dim.Render(fmt.Sprintf("%-9s", label))+ansi.Truncate(value, w-9, "…"))
	}
	files := fmt.Sprintf(" · %d files", d.ChangedFiles)
	if d.ChangedFiles == 1 {
		files = " · 1 file"
	}
	add("branch", d.HeadRefName+dim.Render(" → "+d.BaseRefName))
	add("changes", green.Render(fmt.Sprintf("+%d", d.Additions))+" "+red.Render(fmt.Sprintf("−%d", d.Deletions))+dim.Render(files))
	review := dim.Render("no decision")
	if b, ok := badges[d.ReviewDecision]; ok {
		review = b.String()
	}
	if b, ok := badges[d.Mergeable]; ok {
		review += dim.Render(" · ") + b.String()
	}
	add("review", review)
	summary, failing := checks(d)
	add("checks", summary)
	if failing != "" {
		add("", red.Render(failing))
	}
	return lines
}

// checks counts the checks in each bucket and names the failing ones.
func checks(d *prDetail) (summary, failing string) {
	if d.checksErr != nil {
		return red.Render("unavailable"), ""
	} else if len(d.checks) == 0 {
		return dim.Render("none reported"), ""
	}
	counts, failed := map[string]int{}, []string(nil)
	for _, c := range d.checks {
		counts[c.Bucket]++
		if c.Bucket == "fail" && !slices.Contains(failed, c.Name) {
			failed = append(failed, c.Name)
		}
	}
	var parts []string
	for _, b := range []string{"pass", "fail", "pending", "cancel", "skipping"} {
		if n := counts[b]; n > 0 {
			parts = append(parts, badges[b].UnsetString().Render("●")+fmt.Sprintf(" %d %s", n, badges[b].Value()))
		}
	}
	return strings.Join(parts, "   "), strings.Join(failed, ", ")
}
