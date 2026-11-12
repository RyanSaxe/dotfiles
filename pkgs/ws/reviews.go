package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

	"workspace/kitty"
	"workspace/markdown"
	"workspace/mux"
	"workspace/popup"
)

// reasonTags name why an item needs you, red for what's urgent.
var reasonTags = map[reasonKind]lipgloss.Style{
	failing: popup.Red.SetString("failing"), changesRequested: popup.Red.SetString("changes"),
	reviewed: popup.Yellow.SetString("reviewed"), commented: popup.Yellow.SetString("comment"), opened: popup.Green.SetString("new"),
}

// reviewsPopup lists the inbox `ws attention --watch` last wrote: what needs
// you, and your own open pull requests. It never asks GitHub for the list
// itself, so it opens at once.
func reviewsPopup(b mux.Backend, term kitty.Terminal) popup.Popup {
	noun := "your inbox"
	if _, err := os.Stat(filepath.Join(stateDir, "inbox.json")); err != nil {
		noun = "your inbox for the first time"
	}
	tabs := []popup.Tab{{Name: "Needs you", Empty: "Nothing needs you."}, {Name: "Pull requests", Empty: "You have no open pull requests."},
		{Name: "Issues", Empty: "You have no open issues."}}
	if len(watchList()) > 0 {
		tabs = append(tabs, popup.Tab{Name: "Watching", Empty: "Nothing new in the repositories you watch."})
	}
	return popup.Popup{
		Noun: noun,
		Tabs: tabs,
		Load: func(t int) ([]popup.Row, error) {
			in, err := waitForInbox()
			var a acks
			readJSON("acknowledged.json", &a)
			// Needs you is everything waiting on you, and what lights R. The
			// other tabs are views, not notifications.
			show := []func(item) bool{
				func(it item) bool { return a.standing(it) == needsYou },
				func(it item) bool { return it.Yours && !it.Issue },
				func(it item) bool { return it.Yours && it.Issue },
				func(it item) bool { return it.Watched },
			}[t]
			var rows []popup.Row
			for _, it := range in.Items {
				if !show(it) {
					continue
				}
				rows = append(rows, inboxRow(it, t == 0))
			}
			// Needs you puts the most urgent first, then the newest. The views
			// put whatever changed last first.
			slices.SortStableFunc(rows, func(x, y popup.Row) int {
				if t == 0 {
					p, q := itemOf(x).Reasons[0], itemOf(y).Reasons[0]
					return cmp.Or(int(p.Kind)-int(q.Kind), q.At.Compare(p.At))
				}
				return itemOf(y).Updated.Compare(itemOf(x).Updated)
			})
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			it := itemOf(r)
			text := it.Body
			if !it.Issue {
				text = signedAttachments(text, it.Repo, strconv.Itoa(it.Number))
			}
			// What made it need you comes first, then the description.
			if len(it.Reasons) > 0 && it.Reasons[0].Text != "" {
				why := it.Reasons[0]
				text = fmt.Sprintf("**%s** %s:\n\n%s\n\n---\n\n%s", why.Actor, verbs[why.Kind], why.Text, text)
			}
			return markdown.Load(text, markdownIn("", term)), nil
		},
		Head: inboxHead,
		Body: func(_ popup.Row, d any, w int) string { return d.(markdown.Doc).Render(w, markdownIn("", term)) },
		Actions: []popup.Action{
			{Key: "enter", Help: "review", Run: func(r popup.Row) tea.Cmd {
				it := itemOf(r)
				return tea.Batch(popup.Say("opening #"+strconv.Itoa(it.Number)+"…"), popup.Do(func() error {
					acknowledge(it)
					if it.Issue {
						return browse(it)
					}
					_, err := prWorktree(b, it, "review")
					return err
				}, popup.Quit))
			}},
			{Key: "ctrl+x", Help: "done", Run: func(r popup.Row) tea.Cmd {
				if _, ok := r.Data.(notification); !ok {
					return popup.Say("only Needs you acknowledges")
				}
				it := itemOf(r)
				return popup.Do(func() error { return acknowledge(it) }, popup.Reload("acknowledged #"+strconv.Itoa(it.Number)))
			}},
			{Key: "ctrl+g", Help: "diff", Run: func(r popup.Row) tea.Cmd {
				it := itemOf(r)
				if it.Issue {
					return popup.Say("an issue has no diff")
				}
				diff := fmt.Sprintf("gh pr diff %d -R %s --color=always | delta --paging=always", it.Number, it.Repo)
				return tea.ExecProcess(exec.Command("sh", "-c", diff), func(err error) tea.Msg {
					if err != nil {
						return popup.Notice(err.Error())
					}
					return popup.Notice("")
				})
			}},
			{Key: "ctrl+t", Help: "agent", Run: func(r popup.Row) tea.Cmd {
				it := itemOf(r)
				if it.Issue {
					return popup.Say("an agent reviews pull requests, not issues")
				}
				return tea.Batch(popup.Say("opening an agent on #"+strconv.Itoa(it.Number)+"…"), popup.Do(func() error { return reviewAgent(b, it) }, popup.Quit))
			}},
			{Key: "ctrl+o", Help: "browser", Run: func(r popup.Row) tea.Cmd {
				it := itemOf(r)
				return popup.Do(func() error { return browse(it) }, popup.Notice("opened "+it.URL))
			}},
			{Key: "ctrl+r", Help: "refresh", Always: true, Run: func(popup.Row) tea.Cmd {
				return tea.Batch(popup.Say("refreshing…"), popup.Do(refreshInbox, popup.Reload("refreshed")))
			}},
		},
	}
}

var verbs = map[reasonKind]string{failing: "failed", changesRequested: "asked for changes", reviewed: "reviewed", commented: "commented", opened: "opened it"}

// A notification is an item on Needs you, the only tab that acknowledges.
type notification struct{ item }

// itemOf is the item behind a row on any tab.
func itemOf(r popup.Row) item {
	if n, ok := r.Data.(notification); ok {
		return n.item
	}
	return r.Data.(item)
}

// inboxRow fills a row's four places: the title and why it needs you, then
// the repository, who acted and when. A pull request of yours that needs
// nothing shows where it stands instead.
func inboxRow(it item, needs bool) popup.Row {
	// The number goes with the repository on the second line, so the title
	// gets the whole first line.
	r := popup.Row{ID: it.ID, Title: it.Title, Data: it}
	if needs {
		r.Data = notification{it}
	}
	repo := path.Base(it.Repo) + "#" + strconv.Itoa(it.Number)
	if it.Issue {
		repo = path.Base(it.Repo) + " issue #" + strconv.Itoa(it.Number)
	}
	if needs {
		why := it.Reasons[0]
		// The tag says what happened, so the line under it says who, or which
		// checks failed.
		r.Tag, r.Detail, r.Qualifier = reasonTags[why.Kind], repo+" · "+cmp.Or(why.Actor, "checks"), relAge(why.At)
		return r
	}
	r.Detail, r.Qualifier = repo, relAge(it.Updated)
	switch {
	case it.Draft:
		r.Tag = popup.Yellow.SetString("draft")
	case it.Decision == "APPROVED":
		r.Tag = popup.Green.SetString("approved")
	case it.Decision == "CHANGES_REQUESTED":
		r.Tag = popup.Red.SetString("changes")
	}
	return r
}

// inboxHead is what the row doesn't say: the whole title, which the narrow
// list cuts, then a pull request's branch, size, review and checks.
func inboxHead(r popup.Row, _ any, w int) []string {
	it := itemOf(r)
	lines := []string{popup.Bold.Width(w).Render(it.Title), ""}
	if it.Issue {
		return lines
	}
	add := func(label, value string) {
		lines = append(lines, popup.Dim.Render(fmt.Sprintf("%-9s", label))+ansi.Truncate(value, w-9, "…"))
	}
	files := fmt.Sprintf(" · %d files", it.Files)
	if it.Files == 1 {
		files = " · 1 file"
	}
	add("branch", it.HeadRef+popup.Dim.Render(" → "+it.BaseRef))
	add("changes", popup.Green.Render(fmt.Sprintf("+%d", it.Additions))+" "+popup.Red.Render(fmt.Sprintf("−%d", it.Deletions))+popup.Dim.Render(files))
	review := map[string]string{"APPROVED": popup.Green.Render("approved"), "CHANGES_REQUESTED": popup.Red.Render("changes requested"),
		"REVIEW_REQUIRED": popup.Yellow.Render("review required")}[it.Decision]
	review = cmp.Or(review, popup.Dim.Render("no decision"))
	if it.Mergeable == "CONFLICTING" {
		review += popup.Dim.Render(" · ") + popup.Red.Render("conflicts")
	}
	add("review", review)
	add("checks", checkSummary(it.Checks))
	return append(lines, "")
}

// checkSummary counts the checks by result and names the failing ones.
func checkSummary(cs []check) string {
	if len(cs) == 0 {
		return popup.Dim.Render("none reported")
	}
	counts, failed := map[string]int{}, []string(nil)
	for _, c := range cs {
		counts[c.Result]++
		if c.Result == "fail" {
			failed = append(failed, c.Name)
		}
	}
	styles := map[string]lipgloss.Style{"pass": popup.Green, "fail": popup.Red, "pending": popup.Yellow, "skip": popup.Dim}
	words := map[string]string{"pass": "passed", "fail": "failed", "pending": "pending", "skip": "skipped"}
	var parts []string
	for _, k := range []string{"fail", "pending", "pass", "skip"} {
		if n := counts[k]; n > 0 {
			parts = append(parts, styles[k].Render("●")+fmt.Sprintf(" %d %s", n, words[k]))
		}
	}
	summary := strings.Join(parts, "   ")
	if len(failed) > 0 {
		summary += popup.Red.Render("  " + strings.Join(failed, ", "))
	}
	return summary
}

// waitForInbox reads the inbox, waiting for the job's first fetch when
// there isn't one yet.
func waitForInbox() (inbox, error) {
	var in inbox
	for start := time.Now(); ; time.Sleep(500 * time.Millisecond) {
		err := readJSON("inbox.json", &in)
		if err == nil {
			return in, nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return in, err
		}
		if signalAttention(0) != nil {
			return in, errors.New("there's no inbox yet, and the attention job that fetches it isn't running")
		}
		if time.Since(start) > 2*time.Minute {
			return in, errors.New("the first fetch of your inbox is taking over two minutes")
		}
	}
}

// refreshInbox asks the attention job to fetch now and waits for it to write.
func refreshInbox() error {
	var before inbox
	readJSON("inbox.json", &before)
	if err := signalAttention(syscall.SIGUSR1); err != nil {
		return err
	}
	for start := time.Now(); time.Since(start) < time.Minute; time.Sleep(250 * time.Millisecond) {
		var in inbox
		if readJSON("inbox.json", &in) == nil && in.Fetched.After(before.Fetched) {
			return nil
		}
	}
	return errors.New("the refresh is taking over a minute, so it shows when the job finishes")
}

// acknowledge records the item as it is now, so it stays out of Needs you
// until something new happens on it, and tells the job so R follows.
func acknowledge(it item) error {
	var a acks
	var in inbox
	readJSON("acknowledged.json", &a)
	readJSON("inbox.json", &in)
	if err := writeJSON("acknowledged.json", a.apply(ackEvent{acknowledge: &it, fresh: &in})); err != nil {
		return err
	}
	signalAttention(syscall.SIGUSR2) // without a job, R is unchanged until it starts
	return nil
}

func browse(it item) error {
	kind := "pr"
	if it.Issue {
		kind = "issue"
	}
	_, err := runIn("", "gh", kind, "view", strconv.Itoa(it.Number), "-R", it.Repo, "--web")
	return err
}

// prWorktree opens the pull request's worktree with layout and returns it.
func prWorktree(b mux.Backend, it item, layout string) (string, error) {
	dir := checkoutOf(it.Repo)
	if dir == "" {
		return "", fmt.Errorf("no local checkout of %s under your home folder", it.Repo)
	}
	return pullRequest(b, dir, strconv.Itoa(it.Number), layout)
}

// reviewAgent opens the default agent in a new tab of the pull request's session,
// starting the session first when there's none, with a short review prompt.
func reviewAgent(b mux.Backend, it item) error {
	dir, err := prWorktree(b, it, "review")
	if err != nil {
		return err
	}
	id, err := mux.Find(b, labelFor(dir))
	if err != nil || id == "" {
		return cmp.Or(err, fmt.Errorf("no session for %s", dir))
	}
	prompt := fmt.Sprintf("Review pull request %s. Read its description and its diff with gh, then list what should change before it merges, most important first.", it.URL)
	return b.Tab(id, dir, defaultAgent(), prompt)
}

// signedImage is an attachment's link in a pull request's HTML: signed, so
// it opens without a GitHub session, and named with the attachment's id.
var signedImage = regexp.MustCompile(`"(https://private-user-images\.githubusercontent\.com/\d+/\d+-([0-9a-f-]{36})\.\w+\?jwt=[^"]+)"`)

// signedAttachments swaps the attachments in a pull request's description
// for the signed links GitHub puts in its HTML. A private repository's
// attachments open only that way, and the links expire within minutes, so
// they come with the details.
func signedAttachments(body, repo, num string) string {
	if !strings.Contains(body, "/user-attachments/assets/") {
		return body
	}
	html, err := runIn("", "gh", "api", "repos/"+repo+"/pulls/"+num, "-H", "Accept: application/vnd.github.full+json", "--jq", ".body_html")
	if err != nil {
		return body
	}
	for _, m := range signedImage.FindAllStringSubmatch(html, -1) {
		body = strings.ReplaceAll(body, "https://github.com/user-attachments/assets/"+m[2], strings.ReplaceAll(m[1], "&amp;", "&"))
	}
	return body
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
