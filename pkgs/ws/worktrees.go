package main

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/junegunn/go-shellwords"

	"workspace/layout"
	"workspace/mux"
	"workspace/popup"
)

// startFromAnswer reads the popup's answer to "agent and flags", split into
// words as the shell splits them: an agent, flags for the default agent, or
// both.
func startFromAnswer(answer string) (start, error) {
	parser := shellwords.NewParser()
	words, err := parser.Parse(answer)
	if err == nil && parser.Position >= 0 {
		err = fmt.Errorf("put %q in quotes, or the agent never gets it", answer[parser.Position:])
	}
	s := start{layout: "agent", flags: words}
	if len(words) > 0 && !strings.HasPrefix(words[0], "-") {
		s.agent, s.flags = words[0], words[1:]
	}
	return s, err
}

// worktreesPopup opens on the worktrees of the project ws runs in, with
// every project's on a second tab.
func worktreesPopup(b mux.Backend) popup.Popup {
	project := ""
	if main, err := mainCheckout("."); err == nil {
		project = filepath.Base(main)
	}
	tabs := []popup.Tab{{Name: "Worktrees", Empty: "No worktrees under ~/worktrees."}}
	if project != "" {
		tabs = []popup.Tab{{Name: project, Empty: "No worktrees of " + project + "."}, {Name: "All", Empty: "No worktrees under ~/worktrees."}}
	}
	// The first tab lists only project's worktrees, when there is one.
	onTab := func(t int, w worktree) bool { return project == "" || t != 0 || w.Project == project }
	gather := perLoad(func() ([]worktreeRow, error) {
		wts := worktrees(b)
		bases := perProject(wts, defaultBranch)
		rows := make([]worktreeRow, len(wts))
		for i, w := range wts {
			rows[i] = worktreeRow{worktree: w, base: bases[w.Project]}
		}
		return rows, nil
	})
	pulls := perLoad(func() (map[string]map[string]string, error) { return openPullRequests(worktreeDirs(project)), nil })
	return popup.Popup{
		Noun: "worktrees",
		Tabs: tabs,
		// Each worktree's name and folder show at once, its branch, changes,
		// last commit and agent state once git and the multiplexer answer,
		// and its pull request once GitHub does.
		Load: func(t int, show func([]popup.Row)) ([]popup.Row, error) {
			// GitHub answers last, so it's asked first.
			prs := make(chan map[string]map[string]string, 1)
			go func() { found, _ := pulls(t); prs <- found }()
			var early []popup.Row
			for _, w := range worktreeDirs(project) {
				if onTab(t, w) {
					early = append(early, popup.Row{ID: w.Path, Title: w.Name, Detail: tilde(w.Path), Data: worktreeRow{worktree: w}})
				}
			}
			show(early)
			wts, _ := gather(t)
			var rows []popup.Row
			for _, w := range wts {
				if !onTab(t, w.worktree) {
					continue
				}
				// Only what the tab and the name don't already say: the project on
				// All, the branch where it isn't named after the worktree, and
				// whether it has changes, then the last commit, so the line is
				// never empty.
				var parts []string
				if project == "" || t != 0 {
					parts = append(parts, w.Project)
				}
				if w.Branch != w.Name {
					parts = append(parts, w.Branch)
				}
				if w.Dirty {
					parts = append(parts, "modified")
				}
				meta := strings.Join(append(parts, w.Subject), " · ")
				r := popup.Row{ID: w.Path, Title: w.Name, Detail: meta, Qualifier: relAge(w.Updated), Data: w}
				if s, ok := mux.ParseStatus(w.State); ok {
					r.Tag = statusTag(s)
				}
				rows = append(rows, r)
			}
			show(slices.Clone(rows)) // the frame reads them while the pull requests join these
			openPRs := <-prs
			for i := range rows {
				w := rows[i].Data.(worktreeRow)
				w.pr = openPRs[w.Project][w.Branch]
				rows[i].Data = w
			}
			return rows, nil
		},
		Fetch: func(r popup.Row) (any, error) { return gitSummary(r.Data.(worktreeRow).Path), nil },
		Actions: []popup.Action{
			{Key: "enter", Help: "go", Run: func(r popup.Row) tea.Cmd {
				w := r.Data.(worktreeRow)
				return popup.Do(func() error { return open(b, w.Path, start{}, true) }, popup.Quit)
			}},
			{Key: "ctrl+t", Help: "new", Always: true, Run: func(r popup.Row) tea.Cmd {
				from := "." // with no worktrees yet, the project is the folder ws runs in
				if w, ok := r.Data.(worktreeRow); ok {
					from = w.Path
				}
				return popup.Ask("name:", func(name string) tea.Cmd {
					return popup.Ask("agent and flags (empty for "+layout.Line(agentCommand("", nil))+"):", func(answer string) tea.Cmd {
						return popup.Ask("prompt:", func(prompt string) tea.Cmd {
							return tea.Batch(popup.Say("making "+name+"…"), popup.Do(func() error {
								s, err := startFromAnswer(answer)
								if err != nil {
									return err
								}
								s.prompt = prompt
								main, err := mainCheckout(from)
								if err != nil {
									return err
								}
								return newWorktree(b, main, name, "", s)
							}, popup.Quit))
						})
					})
				})
			}},
			{Key: "ctrl+x", Help: "remove", Run: func(r popup.Row) tea.Cmd {
				w := r.Data.(worktreeRow)
				rm := func(force bool) tea.Cmd {
					return func() tea.Msg {
						if err := remove(b, w.Project+"/"+w.Name, force); err != nil {
							return popup.Reload(err.Error())
						}
						return popup.Reload("removed " + w.Project + "/" + w.Name)
					}
				}
				ask := popup.Ask(w.Name+" has uncommitted changes. Remove it and its branch anyway? (y/N)", func(answer string) tea.Cmd {
					if strings.EqualFold(answer, "y") {
						return rm(true)
					}
					return nil
				})
				// git says now whether it has changes, since a row shown before
				// git answered doesn't know.
				return func() tea.Msg {
					if changes, _ := git(w.Path, "status", "--porcelain"); changes == "" {
						return rm(false)()
					}
					return ask()
				}
			}},
			{Key: "ctrl+f", Help: "files", Run: func(r popup.Row) tea.Cmd {
				return popup.Push(filesPopup(b, r.Data.(worktreeRow).Path))
			}},
			// How the files git tracks changed since the branch left the default
			// branch, committed or not.
			{Key: "ctrl+g", Help: "diff", When: func(_ int, r popup.Row) bool { return r.Data.(worktreeRow).base != "" }, Run: func(r popup.Row) tea.Cmd {
				w := r.Data.(worktreeRow)
				return page(exec.Command("sh", "-c", `git -C "$1" diff --merge-base "$2" | delta --paging=always`, "sh", w.Path, w.base))
			}},
			{Key: "ctrl+o", Help: "browser", When: func(_ int, r popup.Row) bool { return r.Data.(worktreeRow).pr != "" }, Run: func(r popup.Row) tea.Cmd {
				url := r.Data.(worktreeRow).pr
				return popup.Do(func() error {
					_, err := runIn("", "gh", "pr", "view", url, "--web")
					return err
				}, popup.Notice("opened "+url))
			}},
		},
	}
}

// A worktreeRow is a worktree as its popup lists it: base is its project's
// default branch, which its diff starts from, and pr is the URL of its
// branch's open pull request. Each is "" while the popup doesn't know it,
// and when there is none.
type worktreeRow struct {
	worktree
	base, pr string
}

// defaultBranch is the branch origin's HEAD names, such as origin/main, or
// "" when git doesn't know it.
func defaultBranch(dir string) string {
	branch, err := git(dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
	if err != nil {
		return ""
	}
	return branch
}

// perProject runs work once for each project among wts, all at once, in
// one of the project's worktrees, and maps each project to what it returns.
func perProject[T any](wts []worktree, work func(dir string) T) map[string]T {
	var mu sync.Mutex
	var wg sync.WaitGroup
	results, started := map[string]T{}, map[string]bool{}
	for _, w := range wts {
		if started[w.Project] {
			continue
		}
		started[w.Project] = true
		wg.Go(func() {
			result := work(w.Path)
			mu.Lock()
			defer mu.Unlock()
			results[w.Project] = result
		})
	}
	wg.Wait()
	return results
}

// githubRemote reads owner and name from a GitHub remote's URL, over SSH or
// HTTPS.
var githubRemote = regexp.MustCompile(`github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$`)

// openPullRequests asks GitHub, in one call, for the open pull requests of
// each project whose origin is on GitHub, and lists each project's by
// branch. A pull request counts only when its branch is in origin's own
// repository, not a fork's branch of the same name. A repository with more
// than 100 open lists only the 100 updated last.
func openPullRequests(wts []worktree) map[string]map[string]string {
	remotes := perProject(wts, func(dir string) []string {
		url, _ := git(dir, "remote", "get-url", "origin")
		if m := githubRemote.FindStringSubmatch(url); m != nil {
			return m[1:] // owner and name
		}
		return nil
	})
	projects := slices.DeleteFunc(slices.Sorted(maps.Keys(remotes)), func(p string) bool { return remotes[p] == nil })
	if len(projects) == 0 {
		return nil
	}
	var query strings.Builder
	for i, p := range projects {
		fmt.Fprintf(&query, "p%d: repository(owner: %q, name: %q) { pullRequests(states: OPEN, first: 100, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { headRefName url isCrossRepository } } }\n", i, remotes[p][0], remotes[p][1])
	}
	// GitHub answers for every repository it can, and gh fails when it
	// can't answer for one, so the answers are read either way. Without
	// any, such as offline, no worktree shows a pull request. The rows and
	// their details wait for this call, so it gets five seconds.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, "gh", "api", "graphql", "-f", "query={"+query.String()+"}").Output()
	var res struct {
		Data map[string]*struct {
			PullRequests struct {
				Nodes []struct {
					HeadRefName, URL  string
					IsCrossRepository bool
				}
			}
		}
	}
	json.Unmarshal(out, &res)
	found := map[string]map[string]string{}
	for i, p := range projects {
		repo := res.Data["p"+strconv.Itoa(i)]
		if repo == nil {
			continue
		}
		found[p] = map[string]string{}
		for _, pr := range repo.PullRequests.Nodes {
			if _, seen := found[p][pr.HeadRefName]; !seen && !pr.IsCrossRepository {
				found[p][pr.HeadRefName] = pr.URL
			}
		}
	}
	return found
}
