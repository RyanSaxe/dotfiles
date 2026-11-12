// Ws opens folders, worktrees and pull requests as terminal sessions, in Rex
// or tmux, with an agent started in them, and offers popups to move between
// them. State lives with the tools: git owns worktrees and branches, and the
// multiplexer owns sessions, named after their folder.
package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"flag"
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

const usage = `usage:
  ws open DIR [--layout NAME]        open a folder as a session, or switch to its session
  ws new NAME [--agent claude|codex] [--prompt TEXT] [--layout NAME] [--base REF]
                                     make ~/worktrees/PROJECT/NAME on branch NAME and start an agent there
  ws pr NUMBER [--layout NAME]       the same, checked out to a pull request. The review layout opens it in Neovim
  ws send NAME TEXT                  type TEXT and Enter into a session's agent pane
  ws agent [claude|codex]            print the agent this computer starts by default, or set it. With none set,
                                     it is claude when that is installed and codex otherwise
  ws ls [--json]                     list worktrees and their agents
  ws rm NAME [--force]               close a worktree's session, remove it and delete its branch,
                                     but without --force it refuses uncommitted changes and keeps a branch
                                     that isn't merged and whose pull request GitHub doesn't show as merged
  ws pick NAME [--client ID]         open a popup: go, worktrees, reviews, tasks, agents, theme, keys or files.
                                     --from BLOCK starts it in the folder of that Rex pane
  ws tasks --json                    print every task in the vault, for Neovim's pickers
  ws theme                           the theme popup: light or dark, and the mascot
  ws mascot NAME                     set the mascot: a Pokemon by name, shiny-pokemon:NAME, or a PNG file
  ws attention [--watch | --jump]    print what needs you, as agents (waiting or none) and reviews
                                     (ci, review or none). --watch publishes both for sketchybar and
                                     fetches the inbox Reviews lists every 5 minutes, and --jump brings
                                     Rex to the next agent, the one that needs you first
In a popup, typing filters, the arrows, ^j/^k or the wheel move, enter or a click on a row acts,
and esc clears the filter or closes.
Outside Rex and tmux there is no terminal to open a session in, so ws open fails, and ws new and ws pr
only make the worktree and print its path.
Layouts are ~/.config/ws/layouts/NAME.toml, and agent and review are built in. Extra folders for go are ~/.config/ws/bookmarks.
`

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
run = "{agent} {prompt}"
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
		fmt.Print(usage)
		return
	}
	if err := run(os.Args[1], os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "ws:", err)
		os.Exit(1)
	}
}

func run(cmd string, args []string) error {
	fs := flag.NewFlagSet("ws "+cmd, flag.ExitOnError)
	fs.Usage = func() { fmt.Fprint(os.Stderr, usage) }
	layout := fs.String("layout", "agent", "")
	agent := fs.String("agent", "", "")
	prompt := fs.String("prompt", "", "")
	base := fs.String("base", "", "")
	asJSON := fs.Bool("json", false, "")
	force := fs.Bool("force", false, "")
	watch := fs.Bool("watch", false, "")
	jump := fs.Bool("jump", false, "")
	client := fs.String("client", "", "")
	from := fs.String("from", "", "")
	// flag stops at the first argument, so parse again after each one to
	// let flags follow it.
	var pos []string
	for fs.Parse(args); fs.NArg() > 0; fs.Parse(args) {
		pos, args = append(pos, fs.Arg(0)), fs.Args()[1:]
	}
	nargs, known := map[string]int{"open": 1, "new": 1, "pr": 1, "send": 2, "ls": 0, "rm": 1, "pick": 1, "theme": 0, "mascot": 1, "tasks": 0, "attention": 0, "agent": 1}[cmd]
	if !known || len(pos) != nargs && (cmd != "agent" || len(pos) > 0) {
		return errors.New("unknown command or arguments, see ws --help")
	}
	b := mux.Detect(os.Getenv, *client)
	switch cmd {
	case "open":
		dir, _ := filepath.Abs(pos[0])
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			return fmt.Errorf("%s is not a folder", dir)
		}
		return open(b, dir, start{layout: *layout}, true)
	case "new":
		return newWorktree(b, ".", pos[0], *agent, *prompt, *layout, *base)
	case "pr":
		_, err := pullRequest(b, ".", pos[0], *layout)
		return err
	case "agent":
		if len(pos) == 0 {
			fmt.Println(defaultAgent())
			return nil
		}
		return setAgent(pos[0])
	case "send":
		return send(b, pos[0], pos[1])
	case "ls":
		return printWorktrees(b, *asJSON)
	case "rm":
		return remove(b, pos[0], *force)
	case "tasks":
		return printTasks()
	case "theme":
		return pick(b, "theme")
	case "mascot":
		return setMascot(pos[0])
	case "attention":
		return attention(*watch, *jump, *client)
	}
	// A popup's "the project you're in" is the project of the Rex pane it
	// opened from. A float starts in the session's folder otherwise.
	if r, ok := b.(mux.Rex); ok && *from != "" {
		if dir := r.PaneFolder(*from); dir != "" {
			os.Chdir(dir)
		}
	}
	return pick(b, pos[0])
}

// start is how a new session begins: its layout, the agent its agent pane
// runs with a first prompt, and for the review layout the pull request as
// owner/repo/pr/N. The zero value is the agent layout running the default
// agent.
type start struct{ layout, agent, prompt, pr, file string }

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
		vars := map[string]string{"{agent}": cmp.Or(s.agent, defaultAgent()), "{prompt}": s.prompt, "{pr}": s.pr, "{file}": s.file, "{dir}": dir, "{name}": filepath.Base(dir)}
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

func setAgent(name string) error {
	if !slices.Contains(agents, name) {
		return fmt.Errorf("%q is not an agent ws starts, which are %s", name, strings.Join(agents, " and "))
	}
	return writeWhole("agent", []byte(name+"\n"))
}

func newWorktree(b mux.Backend, from, name, agent, prompt, layoutName, base string) error {
	if strings.ContainsAny(name, "/ ") {
		return fmt.Errorf("%q has a slash or space, and a worktree name must be one folder", name)
	}
	main, err := mainCheckout(from)
	if err == nil {
		_, err = layout.Load(layoutsDir, layoutName, builtinLayouts, nil) // a bad layout fails before there is a worktree to clean up
	}
	if err != nil {
		return err
	}
	dir := filepath.Join(worktreeRoot, filepath.Base(main), name)
	if _, err := git(from, append([]string{"worktree", "add", "-b", name, dir}, cmp.Or(base, "HEAD"))...); err != nil {
		return err
	}
	return prepare(b, main, dir, start{layout: layoutName, agent: agent, prompt: prompt})
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
	return dir, prepare(b, main, dir, s)
}

// prepare gives a new worktree the main checkout's ignored files, such as
// .env and .byor, and opens its session.
func prepare(b mux.Backend, main, dir string, s start) error {
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
	return open(b, dir, s, false)
}

// send takes a session label or a worktree name.
func send(b mux.Backend, name, text string) error {
	id, err := mux.Find(b, name)
	if err == nil && id == "" {
		var dir string
		if dir, err = resolveWorktree(name); err != nil {
			return err
		}
		id, err = mux.Find(b, labelFor(dir))
	}
	if err != nil {
		return err
	}
	if id == "" {
		return fmt.Errorf("no session for %s", name)
	}
	return b.Send(id, text)
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

// worktrees lists ~/worktrees/PROJECT/NAME checkouts, the current project
// first and the most recently committed first within a project.
func worktrees(b mux.Backend) []worktree {
	gits, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", "*", ".git"))
	states := b.Statuses()
	wts := make([]worktree, len(gits))
	var wg sync.WaitGroup
	for i, g := range gits {
		dir := filepath.Dir(g)
		wg.Go(func() {
			w := worktree{Project: filepath.Base(filepath.Dir(dir)), Name: filepath.Base(dir), Path: dir}
			if s, ok := states[labelFor(dir)]; ok {
				w.State = s.String()
			}
			status, _ := git(dir, "status", "--porcelain=v2", "--branch")
			for line := range strings.SplitSeq(status, "\n") {
				if b, ok := strings.CutPrefix(line, "# branch.head "); ok {
					w.Branch = b
				} else if line != "" && line[0] != '#' {
					w.Dirty = true
				}
			}
			w.Updated, w.Subject = lastCommit(dir)
			wts[i] = w
		})
	}
	wg.Wait()
	current := ""
	if main, err := mainCheckout("."); err == nil {
		current = filepath.Base(main)
	}
	slices.SortStableFunc(wts, func(a, b worktree) int {
		if mine := a.Project == current; mine != (b.Project == current) {
			if mine {
				return -1
			}
			return 1
		}
		return cmp.Or(strings.Compare(a.Project, b.Project), b.Updated.Compare(a.Updated))
	})
	return wts
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
