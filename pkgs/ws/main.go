// Ws opens folders, worktrees and pull requests as terminal sessions, in Rex
// or tmux, with an agent started in them, and offers popups to move between
// them. State lives with the tools: git owns worktrees and branches, and the
// multiplexer owns sessions, named after their folder.
package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"text/tabwriter"
	"time"

	"github.com/mattn/go-isatty"

	"workspace/layout"
	"workspace/mux"
)

var (
	home, _      = os.UserHomeDir()
	worktreeRoot = filepath.Join(home, "worktrees")
	// interactive means a person ran ws, so it may change what their app or
	// tmux client shows. An agent's output is not a terminal.
	interactive = isatty.IsTerminal(os.Stdout.Fd())
	layoutsDir  = filepath.Join(home, ".config", "ws", "layouts")
)

// The built-in layouts, used when layoutsDir has no file of the name. review
// is a pull request in Neovim: snacks.nvim's view of its conversation, with
// the CodeDiff review a key away.
var builtinLayouts = map[string]string{
	"agent": `
[[pane]]
run = "{agent} -- {prompt}"
focus = true

[[pane]]
split = "right"
size = 35
`,
	"review": `
[[pane]]
run = "nvim gh://{pr}"
focus = true
`,
	"file": `
[[pane]]
run = "nvim {file}"
focus = true
`,
}

// labelFor names a folder's session.
func labelFor(dir string) string { return mux.Label(dir, worktreeRoot) }

// gitHookEnv is what git hands to hooks, which would point every git command
// ws runs at the repository whose hook ran it.
var gitHookEnv = []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"}

func main() {
	for _, v := range gitHookEnv {
		os.Unsetenv(v)
	}
	if len(os.Args) < 2 || slices.Contains([]string{"-h", "--help", "help"}, os.Args[1]) {
		fmt.Print(usage())
		return
	}
	backend := func(client string) mux.Backend { return mux.Detect(os.Getenv, client) }
	if err := run(os.Args[1], os.Args[2:], backend); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// start is how a new session begins: its layout, the agent its agent pane
// runs with its flags and a first prompt, and for the review layout the pull
// request as owner/repo/pr/N. The zero value is the agent layout running the
// default agent with its defaults.
type start struct {
	layout, agent, prompt, pr, file string
	flags                           []string
}

// open shows the session for dir, creating it from the layout when there is
// none. Outside Rex and tmux there is no terminal to create one in, so it
// fails when the caller needs the session, and prints the folder otherwise.
func open(b mux.Backend, dir string, s start, needsSession bool) error {
	label := labelFor(dir)
	id, err := mux.Find(b, label)
	if err != nil {
		return err
	}
	if id == "" && !b.Inside() && needsSession {
		return errors.New("there is no terminal to open a session in, so run this inside Rex or tmux")
	}
	if id == "" && b.Inside() {
		// An empty value fills in no word, so a session without a prompt
		// starts its agent with none.
		word := func(v string) []string {
			if v == "" {
				return nil
			}
			return []string{v}
		}
		vars := map[string][]string{"{agent}": agentCommand(s.agent, s.flags), "{prompt}": word(s.prompt), "{pr}": word(s.pr), "{file}": word(s.file), "{dir}": {dir}, "{name}": {filepath.Base(dir)}}
		panes, err := layout.Load(layoutsDir, cmp.Or(s.layout, "agent"), builtinLayouts, vars)
		if err != nil {
			return err
		}
		if id, err = b.Create(label, dir, panes); err != nil {
			return err
		}
	}
	if id == "" || !interactive {
		fmt.Println(dir)
		return nil
	}
	return b.Show(id)
}

// agents are the programs ws starts as an agent.
var agents = []string{"claude", "codex"}

// defaultAgent is the agent this computer starts when a command names none:
// the one `ws agent` saved, or claude when it is installed and codex otherwise.
func defaultAgent() string {
	data, _ := os.ReadFile(filepath.Join(stateDir, "agent"))
	if saved := strings.TrimSpace(string(data)); slices.Contains(agents, saved) {
		return saved
	}
	if _, err := exec.LookPath("claude"); err != nil {
		return "codex"
	}
	return "claude"
}

// agentFlags are each agent's default flags, which `ws agent` saves.
func agentFlags() map[string][]string {
	flags := map[string][]string{}
	readJSON("agent-flags.json", &flags)
	return flags
}

// agentCommand is the words that start agent, or the default agent when
// agent is empty: the agent and flags, or its defaults when flags is empty.
func agentCommand(agent string, flags []string) []string {
	agent = cmp.Or(agent, defaultAgent())
	if len(flags) == 0 {
		flags = agentFlags()[agent]
	}
	return append([]string{agent}, flags...)
}

// printAgents prints the default agent first, then each other agent that
// has defaults, with its defaults.
func printAgents() {
	def, all := defaultAgent(), agentFlags()
	fmt.Println(layout.Line(append([]string{def}, all[def]...)))
	for _, name := range agents {
		if name != def && len(all[name]) > 0 {
			fmt.Println(layout.Line(append([]string{name}, all[name]...)))
		}
	}
}

// setAgent makes name the default agent. Words after it replace its
// defaults, and a -- with nothing after it clears them.
func setAgent(name string, words []string) error {
	if !slices.Contains(agents, name) {
		return fmt.Errorf("%q is not an agent ws starts, which are %s", name, strings.Join(agents, " and "))
	}
	if len(words) > 0 {
		if words[0] == "--" {
			words = words[1:]
		}
		all := agentFlags()
		all[name] = words
		if len(words) == 0 {
			delete(all, name)
		}
		if err := writeJSON("agent-flags.json", all); err != nil {
			return err
		}
	}
	return writeWhole("agent", []byte(name+"\n"))
}

func newWorktree(b mux.Backend, from, name, base string, s start) error {
	if strings.ContainsAny(name, "/ ") {
		return fmt.Errorf("%q has a slash or space, and a worktree name must be one folder", name)
	}
	if s.agent != "" && !slices.Contains(agents, s.agent) {
		return fmt.Errorf("%q is not an agent ws starts, which are %s", s.agent, strings.Join(agents, " and "))
	}
	main, err := mainCheckout(from)
	if err == nil {
		_, err = layout.Load(layoutsDir, s.layout, builtinLayouts, nil) // a bad layout fails before there is a worktree to clean up
	}
	if err != nil {
		return err
	}
	dir := filepath.Join(worktreeRoot, filepath.Base(main), name)
	label := labelFor(dir)
	// open would go to that session, and start no agent and send no prompt.
	switch id, err := mux.Find(b, label); {
	case err != nil:
		return err
	case id != "":
		return fmt.Errorf("a session named %s is already running, so close it or pick another name", label)
	}
	if _, err := git(from, append([]string{"worktree", "add", "-b", name, dir}, cmp.Or(base, "HEAD"))...); err != nil {
		return err
	}
	if err := copyIgnored(main, dir); err != nil {
		git(main, "worktree", "remove", "--force", dir)
		git(main, "branch", "-D", name)
		return err
	}
	return open(b, dir, s, false)
}

// pullRequest opens a pull request's worktree with layout, which can be
// review: Neovim on the pull request's conversation and review.
func pullRequest(b mux.Backend, from, number, layout string) (string, error) {
	main, err := mainCheckout(from)
	if err != nil {
		return "", err
	}
	view, err := runIn(main, "gh", "pr", "view", number, "--json", "headRefName,url", "--jq", `.headRefName + " " + .url`)
	if err != nil {
		return "", err
	}
	branch, url, _ := strings.Cut(view, " ")
	// snacks.nvim opens gh://owner/repo/pr/N, and the URL ends in owner/repo/pull/N.
	s := start{layout: layout, pr: strings.Replace(strings.TrimPrefix(url, "https://github.com/"), "/pull/", "/pr/", 1)}
	// git lets a branch live in one worktree, so a pull request already
	// checked out somewhere opens there.
	if dir := checkedOut(main, branch); dir != "" {
		return dir, open(b, dir, s, false)
	}
	dir := filepath.Join(worktreeRoot, filepath.Base(main), "pr-"+number)
	if _, err := git(main, "worktree", "add", "--detach", dir); err != nil {
		return "", err
	}
	if _, err := runIn(dir, "gh", "pr", "checkout", number); err != nil {
		git(main, "worktree", "remove", "--force", dir)
		return "", err
	}
	// The branch stays, since gh pr checkout may have reused one you had.
	if err := copyIgnored(main, dir); err != nil {
		git(main, "worktree", "remove", "--force", dir)
		return "", err
	}
	return dir, open(b, dir, s, false)
}

// copyIgnored gives a new worktree the main checkout's ignored files, such
// as .env and .byor.
func copyIgnored(main, dir string) error {
	files, err := exec.Command("git", "-C", main, "ls-files", "--others", "--ignored", "--exclude-standard", "-z").Output()
	if err != nil {
		return fmt.Errorf("listing ignored files: %w", err)
	}
	rsync := exec.Command("rsync", "-a", "--from0", "--files-from=-", "--", main+"/", dir+"/")
	rsync.Stdin = strings.NewReader(string(files))
	if out, err := rsync.CombinedOutput(); err != nil {
		return fmt.Errorf("copying ignored files: %s", out)
	}
	if _, err := os.Stat(filepath.Join(dir, ".byor")); err == nil {
		if _, err := runIn(dir, "byor", "sync"); err != nil {
			return err
		}
	}
	return nil
}

// remove lets git refuse a worktree with uncommitted changes, and closes the
// session last because ws may be running inside it.
func remove(b mux.Backend, name string, force bool) error {
	dir, err := resolveWorktree(name)
	if err != nil {
		return err
	}
	main, err := mainCheckout(dir)
	if err != nil {
		return err
	}
	branch, _ := git(dir, "branch", "--show-current")
	args := []string{"worktree", "remove", dir}
	if force {
		args = append(args, "--force")
	}
	if _, err := git(main, args...); err != nil {
		return err
	}
	var branchErr error
	if branch != "" {
		branchErr = deleteBranch(main, branch, force)
	}
	if id, _ := mux.Find(b, labelFor(dir)); id != "" {
		if err := b.Kill(id); err != nil {
			return err
		}
	}
	return branchErr
}

// deleteBranch deletes a branch git calls merged. A squash merge leaves
// commits git can't find on the base, so a branch git refuses also goes when
// GitHub says its pull request merged. force deletes it either way.
func deleteBranch(main, branch string, force bool) error {
	if force {
		_, err := git(main, "branch", "-D", branch)
		return err
	}
	if _, err := git(main, "branch", "-d", branch); err == nil {
		return nil
	}
	if state, _ := runIn(main, "gh", "pr", "view", branch, "--json", "state", "--jq", ".state"); state != "MERGED" {
		return fmt.Errorf("kept the branch %s: git doesn't call it merged, and GitHub shows no merged pull request for it", branch)
	}
	_, err := git(main, "branch", "-D", branch)
	return err
}

type worktree struct {
	Project string    `json:"project"`
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Branch  string    `json:"branch"`
	Dirty   bool      `json:"dirty"`
	State   string    `json:"state"` // the session's most urgent agent status, "open", or "" with no session
	Updated time.Time `json:"updated"`
	Subject string    `json:"subject"` // the last commit's
}

func printWorktrees(b mux.Backend, asJSON bool) error {
	wts := worktrees(b)
	if asJSON {
		out, err := json.MarshalIndent(wts, "", "  ")
		fmt.Println(string(out))
		return err
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	for i, w := range wts {
		if i == 0 || w.Project != wts[i-1].Project {
			fmt.Fprintln(tw, w.Project)
		}
		fmt.Fprintf(tw, "  %s\t%s\t%s\t%s\n", w.Name, w.Branch, map[bool]string{true: "modified"}[w.Dirty], w.State)
	}
	return tw.Flush()
}

// worktreeDirs lists the ~/worktrees/PROJECT/NAME checkouts with only what
// their folders say, in nearly the order worktrees sorts them in. Until
// worktrees reads the last commit, Updated is when git last moved HEAD,
// which a commit moves too.
func worktreeDirs(current string) []worktree {
	gits, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", "*", ".git"))
	wts := make([]worktree, len(gits))
	for i, g := range gits {
		dir := filepath.Dir(g)
		wts[i] = worktree{Project: filepath.Base(filepath.Dir(dir)), Name: filepath.Base(dir), Path: dir, Updated: activity(dir)}
	}
	sortWorktrees(wts, current)
	return wts
}

// worktrees lists ~/worktrees/PROJECT/NAME checkouts with their branch,
// changes, last commit and agent state, the current project first and the
// most recently committed first within a project.
func worktrees(b mux.Backend) []worktree {
	current := ""
	if main, err := mainCheckout("."); err == nil {
		current = filepath.Base(main)
	}
	wts := worktreeDirs(current)
	var states map[string]mux.Status
	var wg sync.WaitGroup
	wg.Go(func() {
		s, _ := b.Snapshot()
		states = s.Statuses()
	})
	for i := range wts {
		w := &wts[i]
		wg.Go(func() {
			status, _ := git(w.Path, "status", "--porcelain=v2", "--branch")
			for line := range strings.SplitSeq(status, "\n") {
				if b, ok := strings.CutPrefix(line, "# branch.head "); ok {
					w.Branch = b
				} else if line != "" && line[0] != '#' {
					w.Dirty = true
				}
			}
			w.Updated, w.Subject = lastCommit(w.Path)
		})
	}
	wg.Wait()
	for i, w := range wts {
		if s, ok := states[labelFor(w.Path)]; ok {
			wts[i].State = s.String()
		}
	}
	sortWorktrees(wts, current)
	return wts
}

// sortWorktrees puts current's worktrees first, then each project's, the
// most recently committed first.
func sortWorktrees(wts []worktree, current string) {
	slices.SortStableFunc(wts, func(a, b worktree) int {
		if mine := a.Project == current; mine != (b.Project == current) {
			if mine {
				return -1
			}
			return 1
		}
		return cmp.Or(strings.Compare(a.Project, b.Project), b.Updated.Compare(a.Updated))
	})
}

// resolveWorktree finds ~/worktrees/PROJECT/NAME from PROJECT/NAME or a NAME
// that only one project has, preferring the current project.
func resolveWorktree(name string) (string, error) {
	if strings.Contains(name, "/") {
		dir := filepath.Join(worktreeRoot, name)
		_, err := os.Stat(filepath.Join(dir, ".git"))
		return dir, err
	}
	matches, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", name, ".git"))
	if main, err := mainCheckout("."); err == nil {
		if mine := filepath.Join(worktreeRoot, filepath.Base(main), name, ".git"); slices.Contains(matches, mine) {
			matches = []string{mine}
		}
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("no worktree named %s under %s", name, worktreeRoot)
	case 1:
		return filepath.Dir(matches[0]), nil
	}
	return "", fmt.Errorf("several projects have a worktree named %s, so name it as PROJECT/%s", name, name)
}

// mainCheckout is the repository's first working tree, the one its
// worktrees copy ignored files from and are named after.
func mainCheckout(dir string) (string, error) {
	common, err := git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
	return filepath.Dir(common), err
}

func checkedOut(repo, branch string) string {
	out, _ := git(repo, "worktree", "list", "--porcelain")
	var dir string
	for line := range strings.SplitSeq(out, "\n") {
		if d, ok := strings.CutPrefix(line, "worktree "); ok {
			dir = d
		} else if line == "branch refs/heads/"+branch {
			return dir
		}
	}
	return ""
}

// lastCommit is when the folder's last commit was made, and its subject.
func lastCommit(dir string) (time.Time, string) {
	out, _ := git(dir, "log", "-1", "--format=%cI%x00%s")
	at, subject, _ := strings.Cut(out, "\x00")
	t, _ := time.Parse(time.RFC3339, at)
	return t, subject
}

func git(dir string, args ...string) (string, error) {
	return runIn("", "git", append([]string{"-C", dir}, args...)...)
}

// runIn runs a program in dir and returns its trimmed output. A failure
// reads as what the program printed to stderr.
func runIn(dir, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if msg := strings.TrimSpace(stderr.String()); err != nil && msg != "" {
		err = fmt.Errorf("%s: %s", name, msg)
	}
	return strings.TrimSpace(string(out)), err
}
