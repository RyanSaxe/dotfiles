package main

import (
	"cmp"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
	"workspace/mux"
	"workspace/popup"

	tea "github.com/charmbracelet/bubbletea"
)

// A checkout is a repository the walk found: its folder, the GitHub
// repository its origin names as owner/name, or "" for none, and when git
// last moved its HEAD.
type checkout struct {
	dir, repo string
	at        time.Time
}

// checkouts lists the repositories under the home folder, with their
// GitHub repositories.
func checkouts() []checkout {
	var cs []checkout
	for _, dir := range repos() {
		cs = append(cs, checkout{dir, originRepo(dir), activity(dir)})
	}
	return cs
}

// originRepo is owner/name of the GitHub repository dir's origin names, or
// "". It reads git's config file, since asking git costs a process per
// folder. A checkout whose .git is a file keeps its config elsewhere, so
// git is asked about that one.
func originRepo(dir string) string {
	url := ""
	if data, err := os.ReadFile(filepath.Join(dir, ".git", "config")); err == nil { //nolint:gosec // reads local git config in discovered repo
		inOrigin := false
		for line := range strings.SplitSeq(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "[") {
				inOrigin = line == `[remote "origin"]`
			} else if key, value, ok := strings.Cut(line, "="); ok && inOrigin && strings.TrimSpace(key) == "url" {
				url = strings.TrimSpace(value)
			}
		}
	} else {
		url, _ = git(dir, "remote", "get-url", "origin")
	}
	if m := githubRemote.FindStringSubmatch(url); m != nil {
		return m[1] + "/" + m[2]
	}
	return ""
}

// topFolder is the folder right under the home folder that holds dir, or
// "" for a folder right under home.
func topFolder(dir string) string {
	rel, err := filepath.Rel(home, dir)
	first, _, nested := strings.Cut(rel, string(filepath.Separator))
	if err != nil || !nested || first == ".." {
		return ""
	}
	return filepath.Join(home, first)
}

// folderChoices are the folders right under home that hold repositories,
// the one that holds the most first.
func folderChoices(cs []checkout) []string {
	held := map[string]int{}
	for _, c := range cs {
		if top := topFolder(c.dir); top != "" {
			held[top]++
		}
	}
	return slices.SortedFunc(maps.Keys(held), func(a, b string) int { return cmp.Or(held[b]-held[a], strings.Compare(a, b)) })
}

// ownerRepo is owner/name, as gh repo clone takes it.
var ownerRepo = regexp.MustCompile(`^([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?$`)

// A project is what ws project makes of its answer: a repository to clone,
// or a new one to make with git init, in a folder named name inside
// parent. existing is a checkout of repo already here, which ws only
// opens. trust says to trust it before its agent starts.
type project struct {
	repo, name, parent, existing string
	trust                        bool
}

func parseProjectAnswer(answer string) (project, error) {
	answer = strings.TrimSpace(answer)
	switch url, repo := githubRemote.FindStringSubmatch(answer), ownerRepo.FindStringSubmatch(answer); {
	case url != nil:
		return project{repo: url[1] + "/" + url[2], name: url[2]}, nil
	case repo != nil:
		return project{repo: repo[1] + "/" + repo[2], name: repo[2]}, nil
	case answer == "" || answer == "." || answer == ".." || strings.ContainsAny(answer, "/ "):
		return project{}, fmt.Errorf("%q isn't a project name, owner/repo or GitHub URL", answer)
	default:
		return project{name: answer, trust: true}, nil // ws makes it with git init
	}
}

func bestOwnerParent(held map[string]int, latest map[string]time.Time) string {
	parent := ""
	for _, top := range slices.Sorted(maps.Keys(held)) {
		if parent == "" || held[top] > held[parent] || held[top] == held[parent] && latest[top].After(latest[parent]) {
			parent = top
		}
	}
	return parent
}

// planProject reads answer, a new project's name, owner/name or a GitHub
// URL, and finds where it goes among cs. A clone goes in the folder right
// under home that holds most of its owner's repositories, the one with the
// owner's latest activity on a tie. A new project, and a clone from an
// owner with no repository here, leave parent for the caller to choose.
func planProject(answer string, cs []checkout) (project, error) {
	p, err := parseProjectAnswer(answer)
	if err != nil || p.repo == "" {
		return p, err
	}
	owner, _, _ := strings.Cut(p.repo, "/")
	held, latest := map[string]int{}, map[string]time.Time{}
	for _, c := range cs {
		if strings.EqualFold(c.repo, p.repo) {
			p.existing = c.dir
		}
		if theirs, _, _ := strings.Cut(c.repo, "/"); strings.EqualFold(theirs, owner) {
			p.trust = true // the owner has repositories here
			if top := topFolder(c.dir); top != "" {
				held[top]++
				if c.at.After(latest[top]) {
					latest[top] = c.at
				}
			}
		}
	}
	p.parent = bestOwnerParent(held, latest)
	return p, nil
}

// needsFolder says whether someone must choose the folder p goes in.
func (p project) needsFolder() bool { return p.parent == "" && p.existing == "" }

// checkTarget ensures p's target directory is free and has no running session.
// It returns an already-cloned path when dir holds p's repository.
func (p project) checkTarget(b mux.Backend, dir string) (string, error) {
	if _, err := os.Lstat(dir); !errors.Is(err, os.ErrNotExist) {
		if p.repo != "" && strings.EqualFold(originRepo(dir), p.repo) {
			return dir, nil
		}
		return "", fmt.Errorf("%s is taken, so ws made nothing", tilde(dir))
	}
	switch _, found, err := mux.Find(b, labelFor(dir)); {
	case err != nil:
		return "", err
	case found:
		return "", fmt.Errorf("a session named %s is already running, so close it first", labelFor(dir))
	}
	return "", nil
}

// make clones or makes p and trusts it when it should, and returns its
// folder. A folder that already holds p's repository is only returned. Any
// other folder of p's name, or a running session of its name, which open
// would go to instead, stops it before it makes anything.
func (p project) make(b mux.Backend) (string, error) {
	if p.existing != "" {
		return p.existing, nil
	}
	parent, err := filepath.EvalSymlinks(p.parent)
	if info, statErr := os.Stat(parent); err != nil || statErr != nil || !info.IsDir() {
		return "", fmt.Errorf("%s is not a folder", tilde(p.parent))
	}
	dir := filepath.Join(p.parent, p.name)
	if existing, err := p.checkTarget(b, dir); err != nil || existing != "" {
		return existing, err
	}
	// Trusting it first means a failure leaves nothing made, so trying again
	// works.
	if p.trust {
		if err := trustFolder(filepath.Join(parent, p.name)); err != nil {
			return "", err
		}
	}
	return p.createDir(dir)
}

func (p project) createDir(dir string) (string, error) {
	if p.repo != "" {
		_, err := runIn("", "gh", "repo", "clone", p.repo, dir)
		return dir, err
	}
	if err := os.Mkdir(dir, 0o750); err != nil {
		return "", err
	}
	_, err := git(dir, "init", "-q")
	return dir, err
}

// start is how p's session begins: a new project's agent sets it up.
func (p project) start() start {
	if p.repo == "" && p.existing == "" {
		return start{prompt: "Set up this project"}
	}
	return start{}
}

// makeAndOpen makes p in the popup and opens it, as Enter on a folder does.
func (p project) makeAndOpen(b mux.Backend) tea.Cmd {
	doing := "making " + p.name + "…"
	if p.existing != "" {
		doing = "opening " + tilde(p.existing) + "…"
	} else if p.repo != "" {
		doing = "cloning " + p.repo + "…"
	}
	return tea.Batch(popup.Say(doing), popup.Do(func() error {
		dir, err := p.make(b)
		if err != nil {
			return err
		}
		return open(b, dir, p.start(), true)
	}, popup.Quit))
}

// newProject is the Folders tab's Ctrl-T: it asks for a project, and for
// its folder when ws can't tell where it goes.
func newProject(b mux.Backend) tea.Cmd {
	return popup.Ask("new project's name, owner/repo or GitHub URL:", func(answer string) tea.Cmd {
		cs := checkouts()
		p, err := planProject(answer, cs)
		switch {
		case err != nil:
			return popup.Say(err.Error())
		case p.needsFolder():
			return popup.Push(wherePopup(b, p, folderChoices(cs)))
		}
		return p.makeAndOpen(b)
	})
}

// wherePopup asks which folder p goes in, among choices.
func wherePopup(b mux.Backend, p project, choices []string) popup.Popup {
	return popup.Popup{
		Noun: "folders", OneLine: true,
		Tabs: []popup.Tab{{Name: "Where does " + p.name + " go?", Empty: "No folder under ~ holds a repository, so use ws project NAME --in DIR."}},
		Load: func(int, func([]popup.Row)) ([]popup.Row, error) {
			rows := make([]popup.Row, len(choices))
			for i, dir := range choices {
				rows[i] = popup.Row{ID: dir, Title: tilde(dir), Data: dir}
			}
			return rows, nil
		},
		Actions: []popup.Action{{Key: "enter", Help: "put it here", Run: func(r popup.Row) tea.Cmd {
			p.parent = r.Data.(string)
			return p.makeAndOpen(b)
		}}},
	}
}

// oneOf names dirs as choices, as in "~/a, ~/b or ~/c".
func oneOf(dirs []string) string {
	names := make([]string, len(dirs))
	for i, d := range dirs {
		names[i] = tilde(d)
	}
	switch len(names) {
	case 0:
		return "a folder under ~"
	case 1:
		return names[0]
	}
	return strings.Join(names[:len(names)-1], ", ") + " or " + names[len(names)-1]
}
