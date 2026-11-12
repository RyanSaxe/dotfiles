package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

// The inbox is what Reviews lists: the open pull requests and issues that
// involve you, each with the reasons it needs you. `ws attention --watch` is
// the only thing that fetches it and writes inbox.json, and the popup only
// reads it. Your acknowledgements are the one thing ws keeps for it, in
// acknowledged.json, which only the popup writes.

// A reasonKind is why an item needs you, most urgent first.
type reasonKind int

const (
	failing          reasonKind = iota // checks went red on your pull request
	changesRequested                   // a review asked for changes on yours
	reviewed                           // someone else reviewed yours
	commented                          // someone wrote after your last reply or reaction
	opened                             // someone else's, new this week in a repository you watch
)

type reason struct {
	Kind  reasonKind
	Actor string // who, or for failing the checks that failed
	At    time.Time
	Key   string // the comment, review or commit it's about
	Text  string // what they wrote, shown first in the details
}

type item struct {
	ID, URL, Title, Repo, Author, Body    string
	Number                                int
	Issue, Draft, Yours                   bool
	Updated                               time.Time
	HeadRef, BaseRef, Decision, Mergeable string
	Additions, Deletions, Files           int
	Checks                                []check
	Reasons                               []reason // most urgent first
	Watched                               bool     // in a repository you watch
}

type check struct{ Name, Result string } // Result is pass, fail, pending or skip

type inbox struct {
	Fetched time.Time
	Items   []item
}

// activity names everything an item needs you for. Acknowledging keeps it,
// and anything newer changes it.
func (it item) activity() string {
	keys := make([]string, len(it.Reasons))
	for i, r := range it.Reasons {
		keys[i] = fmt.Sprint(int(r.Kind), ":", r.Key)
	}
	return strings.Join(keys, " ")
}

// A standing is whether an item needs you.
type standing int

const (
	clear        standing = iota // nothing needs you
	needsYou                     // a reason you haven't acknowledged
	acknowledged                 // nothing new since you acknowledged it
)

// acks maps each item you acknowledged to its activity then.
type acks map[string]string

func (a acks) standing(it item) standing {
	switch {
	case len(it.Reasons) == 0:
		return clear
	case a[it.ID] == it.activity():
		return acknowledged
	}
	return needsYou
}

// An ackEvent moves acks: you acknowledge an item as it is now, or a fresh
// inbox arrives and the records of items that closed go.
type ackEvent struct {
	acknowledge *item
	fresh       *inbox
}

func (a acks) apply(e ackEvent) acks {
	next := acks{}
	for id, key := range a {
		next[id] = key
	}
	if e.acknowledge != nil {
		next[e.acknowledge.ID] = e.acknowledge.activity()
	}
	if e.fresh != nil {
		open := map[string]bool{}
		for _, it := range e.fresh.Items {
			open[it.ID] = true
		}
		for id := range next {
			if !open[id] {
				delete(next, id)
			}
		}
	}
	return next
}

// stateDir holds what ws keeps between runs. XDG_STATE_HOME moves it, so a
// scratch run never touches the real one.
var stateDir = filepath.Join(cmp.Or(os.Getenv("XDG_STATE_HOME"), filepath.Join(home, ".local", "state")), "ws")

func readJSON(name string, v any) error {
	data, err := os.ReadFile(filepath.Join(stateDir, name))
	if err == nil {
		err = json.Unmarshal(data, v)
	}
	return err
}

// writeJSON swaps the file in whole, so a reader never sees half of it.
func writeJSON(name string, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return writeWhole(name, data)
}

func writeWhole(name string, data []byte) error {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(stateDir, "."+name+"-*")
	if err != nil {
		return err
	}
	if _, err = tmp.Write(data); err == nil {
		err = tmp.Close()
	}
	if err == nil {
		err = os.Rename(tmp.Name(), filepath.Join(stateDir, name))
	}
	if err != nil {
		os.Remove(tmp.Name())
	}
	return err
}

// GitHub's view of an item, as the queries below ask for it.
type ghActor struct {
	Login string
	Type  string `json:"__typename"`
}

func (a *ghActor) person() bool { return a != nil && a.Type == "User" }

type ghComment struct {
	ID, Body       string
	CreatedAt      time.Time
	Author         *ghActor
	ReactionGroups []struct{ ViewerHasReacted bool }
}

type ghNode struct {
	Type                               string `json:"__typename"`
	ID, Title, URL, Body               string
	Number                             int
	IsDraft                            bool
	CreatedAt, UpdatedAt               time.Time
	Repository                         struct{ NameWithOwner string }
	Author                             *ghActor
	Additions, Deletions, ChangedFiles int
	ReviewDecision, Mergeable          string
	HeadRefName, BaseRefName           string
	Comments                           struct{ Nodes []ghComment }
	ReviewThreads                      struct {
		Nodes []struct{ Comments struct{ Nodes []ghComment } }
	}
	Reviews struct{ Nodes []ghReview }
	Commits struct{ Nodes []struct{ Commit ghCommit } }
}

type ghReview struct {
	ID, State, Body string
	SubmittedAt     time.Time
	Author          *ghActor
}

type ghCommit struct {
	Oid               string
	StatusCheckRollup *struct {
		State    string
		Contexts struct {
			Nodes []struct{ Name, Conclusion, Context, State string }
		}
	}
}

var mention = regexp.MustCompile(`@([A-Za-z0-9-]+)`)

// reasonsFor applies the rail's four rules to one item. me is your GitHub
// login, and watched says whether the item's repository is on your watch
// list.
func reasonsFor(n ghNode, me string, watched bool, now time.Time) []reason {
	mine := func(a *ghActor) bool { return a != nil && strings.EqualFold(a.Login, me) }
	comments := n.Comments.Nodes
	for _, t := range n.ReviewThreads.Nodes {
		comments = append(comments, t.Comments.Nodes...)
	}
	yours, tookPart := mine(n.Author), false
	var theirs, answered *ghComment
	for i, c := range comments {
		mentioned := slices.ContainsFunc(mention.FindAllStringSubmatch(c.Body, -1), func(m []string) bool { return strings.EqualFold(m[1], me) })
		if mine(c.Author) || c.Author.person() && mentioned {
			tookPart = true
		}
		reacted := slices.ContainsFunc(c.ReactionGroups, func(g struct{ ViewerHasReacted bool }) bool { return g.ViewerHasReacted })
		if (mine(c.Author) || reacted) && (answered == nil || c.CreatedAt.After(answered.CreatedAt)) {
			answered = &comments[i]
		}
		if c.Author.person() && !mine(c.Author) && (theirs == nil || c.CreatedAt.After(theirs.CreatedAt)) {
			theirs = &comments[i]
		}
	}
	var rs []reason
	if pr := n.Type == "PullRequest"; pr && yours {
		if cs := n.Commits.Nodes; len(cs) > 0 && cs[0].Commit.StatusCheckRollup != nil {
			if s := cs[0].Commit.StatusCheckRollup.State; s == "FAILURE" || s == "ERROR" {
				rs = append(rs, reason{Kind: failing, Actor: failedChecks(cs[0].Commit), At: n.UpdatedAt, Key: cs[0].Commit.Oid})
			}
		}
		var last *ghReview
		for i, r := range n.Reviews.Nodes {
			if r.State != "DISMISSED" && r.Author.person() && !mine(r.Author) && (last == nil || r.SubmittedAt.After(last.SubmittedAt)) {
				last = &n.Reviews.Nodes[i]
			}
		}
		if last != nil {
			kind := reviewed
			if last.State == "CHANGES_REQUESTED" {
				kind = changesRequested
			}
			rs = append(rs, reason{Kind: kind, Actor: last.Author.Login, At: last.SubmittedAt, Key: last.ID, Text: last.Body})
		}
	}
	if (yours || tookPart) && theirs != nil && (answered == nil || theirs.CreatedAt.After(answered.CreatedAt)) {
		rs = append(rs, reason{Kind: commented, Actor: theirs.Author.Login, At: theirs.CreatedAt, Key: theirs.ID, Text: theirs.Body})
	}
	if watched && !mine(n.Author) && !n.IsDraft && n.Author.person() && now.Sub(n.CreatedAt) < 7*24*time.Hour {
		rs = append(rs, reason{Kind: opened, Actor: n.Author.Login, At: n.CreatedAt, Key: n.ID})
	}
	slices.SortStableFunc(rs, func(a, b reason) int { return int(a.Kind) - int(b.Kind) })
	return rs
}

func failedChecks(c ghCommit) string {
	var names []string
	for _, x := range c.StatusCheckRollup.Contexts.Nodes {
		if r := cmp.Or(x.Conclusion, x.State); r == "FAILURE" || r == "ERROR" || r == "TIMED_OUT" {
			names = append(names, cmp.Or(x.Name, x.Context))
		}
	}
	return strings.Join(names, ", ")
}

func itemFrom(n ghNode, me string, watched bool, now time.Time) item {
	it := item{ID: n.ID, URL: n.URL, Title: n.Title, Repo: n.Repository.NameWithOwner, Body: n.Body, Number: n.Number,
		Issue: n.Type == "Issue", Draft: n.IsDraft, Updated: n.UpdatedAt, HeadRef: n.HeadRefName, BaseRef: n.BaseRefName,
		Decision: n.ReviewDecision, Mergeable: n.Mergeable, Additions: n.Additions, Deletions: n.Deletions, Files: n.ChangedFiles,
		Reasons: reasonsFor(n, me, watched, now)}
	if n.Author != nil {
		it.Author, it.Yours = n.Author.Login, strings.EqualFold(n.Author.Login, me)
	}
	it.Watched = watched
	if cs := n.Commits.Nodes; len(cs) > 0 && cs[0].Commit.StatusCheckRollup != nil {
		for _, x := range cs[0].Commit.StatusCheckRollup.Contexts.Nodes {
			result := map[string]string{"SUCCESS": "pass", "FAILURE": "fail", "ERROR": "fail", "TIMED_OUT": "fail", "SKIPPED": "skip", "NEUTRAL": "skip"}[cmp.Or(x.Conclusion, x.State)]
			it.Checks = append(it.Checks, check{cmp.Or(x.Name, x.Context), cmp.Or(result, "pending")})
		}
	}
	return it
}

// The fields both queries ask for. Comments and reviews are only the last
// few, since the rules look at the newest.
const itemFields = `
  ... on PullRequest {
    __typename id number title url body createdAt updatedAt isDraft
    repository { nameWithOwner } author { login __typename }
    additions deletions changedFiles reviewDecision mergeable headRefName baseRefName
    comments(last: 20) { nodes { id createdAt body author { login __typename } reactionGroups { viewerHasReacted } } }
    reviewThreads(last: 10) { nodes { comments(last: 5) { nodes { id createdAt body author { login __typename } reactionGroups { viewerHasReacted } } } } }
    reviews(last: 10) { nodes { id state submittedAt body author { login __typename } } }
    commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts(first: 50) { nodes { ... on CheckRun { name conclusion } ... on StatusContext { context state } } } } } } }
  }
  ... on Issue {
    __typename id number title url body createdAt updatedAt
    repository { nameWithOwner } author { login __typename }
    comments(last: 20) { nodes { id createdAt body author { login __typename } reactionGroups { viewerHasReacted } } }
  }`

func graphql(query string, out any) error {
	raw, err := runIn("", "gh", "api", "graphql", "-f", "query="+query)
	if err != nil {
		return err
	}
	var res struct {
		Data   json.RawMessage
		Errors []struct{ Message string }
	}
	if err := json.Unmarshal([]byte(raw), &res); err != nil {
		return err
	}
	if len(res.Errors) > 0 {
		return errors.New(res.Errors[0].Message)
	}
	return json.Unmarshal(res.Data, out)
}

// fetchInbox asks GitHub which items involve you or are new in a watched
// repository, then fetches the details of only those that changed since prev.
func fetchInbox(prev inbox, watch []string, now time.Time) (inbox, error) {
	searches := []string{"is:open involves:@me updated:>=" + now.AddDate(0, 0, -90).Format(time.DateOnly)}
	if len(watch) > 0 {
		searches = append(searches, "is:open updated:>="+now.AddDate(0, 0, -90).Format(time.DateOnly)+" repo:"+strings.Join(watch, " repo:"))
	}
	me, updated := "", map[string]time.Time{}
	for _, q := range searches {
		after := "null"
		for {
			var page struct {
				Viewer struct{ Login string }
				Search struct {
					PageInfo struct {
						HasNextPage bool
						EndCursor   string
					}
					Nodes []struct {
						ID        string
						UpdatedAt time.Time
					}
				}
			}
			err := graphql(fmt.Sprintf(`query { viewer { login } search(query: %q, type: ISSUE, first: 100, after: %s) {
  pageInfo { hasNextPage endCursor } nodes { ... on PullRequest { id updatedAt } ... on Issue { id updatedAt } } } }`, q, after), &page)
			if err != nil {
				return prev, err
			}
			me = page.Viewer.Login
			for _, n := range page.Search.Nodes {
				updated[n.ID] = n.UpdatedAt
			}
			if !page.Search.PageInfo.HasNextPage {
				break
			}
			after = fmt.Sprintf("%q", page.Search.PageInfo.EndCursor)
		}
	}
	kept := map[string]item{}
	for _, it := range prev.Items {
		if at, ok := updated[it.ID]; ok && at.Equal(it.Updated) {
			it.Reasons = slices.DeleteFunc(it.Reasons, func(r reason) bool { return r.Kind == opened && now.Sub(r.At) >= 7*24*time.Hour })
			kept[it.ID] = it
		}
	}
	var changed []string
	for id := range updated {
		if _, ok := kept[id]; !ok {
			changed = append(changed, id)
		}
	}
	watched := map[string]bool{}
	for _, r := range watch {
		watched[strings.ToLower(r)] = true
	}
	// 25 at a time, since a larger batch of full details times out.
	for batch := range slices.Chunk(changed, 25) {
		ids, _ := json.Marshal(batch)
		var res struct{ Nodes []ghNode }
		if err := graphql(fmt.Sprintf("query { nodes(ids: %s) {%s\n} }", ids, itemFields), &res); err != nil {
			return prev, err
		}
		for _, n := range res.Nodes {
			if n.ID != "" {
				kept[n.ID] = itemFrom(n, me, watched[strings.ToLower(n.Repository.NameWithOwner)], now)
			}
		}
	}
	next := inbox{Fetched: now}
	for _, it := range kept {
		next.Items = append(next.Items, it)
	}
	slices.SortFunc(next.Items, func(a, b item) int { return b.Updated.Compare(a.Updated) })
	return next, nil
}

// watchList is the repositories whose new items need you, one owner/name
// per line or space, from the secrets file. None is fine.
func watchList() []string {
	data, _ := os.ReadFile(filepath.Join(home, ".config", "sops-nix", "secrets", "attention-watch"))
	return strings.Fields(string(data))
}
