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
)

const usage = `usage:
  ws open DIR [--layout NAME]        open a folder as a session, or switch to its session
  ws new NAME [--agent claude|codex] [--prompt TEXT] [--layout NAME] [--base REF]
                                     make ~/worktrees/PROJECT/NAME on branch NAME and start an agent there
  ws pr NUMBER                       the same, checked out to a pull request
  ws send NAME TEXT                  type TEXT and Enter into a session's agent pane
  ws ls [--json]                     list worktrees and their agents
  ws rm NAME [--force]               close a worktree's session, remove it and delete its branch,
                                     but without --force it refuses uncommitted changes and keeps an unmerged branch
Layouts are ~/.config/ws/layouts/NAME.toml. Extra folders for go are ~/.config/ws/bookmarks.
`

var (
	home, _      = os.UserHomeDir()
	worktreeRoot = filepath.Join(home, "worktrees")
	// interactive means a person ran ws, so it may change what their app or
	// tmux client shows. An agent's output is not a terminal.
	interactive = isatty.IsTerminal(os.Stdout.Fd())
	client      string // the Rex app to switch, from --client
)

func main() {
	// git hands these to hooks, and they would point every git command ws
	// runs at the repository whose hook ran it.
	for _, v := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"} {
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
	agent := fs.String("agent", "claude", "")
	prompt := fs.String("prompt", "", "")
	base := fs.String("base", "", "")
	asJSON := fs.Bool("json", false, "")
	force := fs.Bool("force", false, "")
	fs.StringVar(&client, "client", "", "")
	// flag stops at the first argument, so parse again after each one to
	// let flags follow it.
	var pos []string
	for fs.Parse(args); fs.NArg() > 0; fs.Parse(args) {
		pos, args = append(pos, fs.Arg(0)), fs.Args()[1:]
	}
	nargs, known := map[string]int{"open": 1, "new": 1, "pr": 1, "send": 2, "ls": 0, "rm": 1}[cmd]
	if !known || len(pos) != nargs {
		return errors.New("unknown command or arguments, see ws --help")
	}
	switch cmd {
	case "open":
		dir, _ := filepath.Abs(pos[0])
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			return fmt.Errorf("%s is not a folder", dir)
		}
		return open(dir, *layout, "claude", "", true)
	case "new":
		return newWorktree(".", pos[0], *agent, *prompt, *layout, *base)
	case "pr":
		return pullRequest(".", pos[0])
	case "send":
		return send(pos[0], pos[1])
	case "ls":
		return printWorktrees(*asJSON)
	}
	return remove(pos[0], *force)
}

// open shows the session for dir, creating it from the layout when there is
// none. Outside Rex and tmux there is nothing to show, so it prints the
// folder, unless mayStart lets a person get a new tmux session.
func open(dir, layout, agent, prompt string, mayStart bool) error {
	m, label := mux(), labelFor(dir)
	id, err := find(m, label)
	if err != nil {
		return err
	}
	if id == "" && (inRex || inTmux || mayStart && interactive) {
		vars := map[string]string{"{agent}": agent, "{prompt}": prompt, "{dir}": dir, "{name}": filepath.Base(dir)}
		panes, err := loadLayout(layout, vars)
		if err != nil {
			return err
		}
		if id, err = m.create(label, dir, panes); err != nil {
			return err
		}
	}
	if id == "" || !interactive {
		fmt.Println(dir)
		return nil
	}
	return m.show(id)
}

func newWorktree(from, name, agent, prompt, layout, base string) error {
	if strings.ContainsAny(name, "/ ") {
		return fmt.Errorf("%q has a slash or space, and a worktree name must be one folder", name)
	}
	main, err := mainCheckout(from)
	if err == nil {
		_, err = loadLayout(layout, nil) // a bad layout fails before there is a worktree to clean up
	}
	if err != nil {
		return err
	}
	dir := filepath.Join(worktreeRoot, filepath.Base(main), name)
	if _, err := git(from, append([]string{"worktree", "add", "-b", name, dir}, cmp.Or(base, "HEAD"))...); err != nil {
		return err
	}
	return prepare(main, dir, layout, agent, prompt)
}

func pullRequest(from, number string) error {
	main, err := mainCheckout(from)
	if err != nil {
		return err
	}
	branch, err := runIn(main, "gh", "pr", "view", number, "--json", "headRefName", "--jq", ".headRefName")
	if err != nil {
		return err
	}
	// git lets a branch live in one worktree, so a pull request already
	// checked out somewhere opens there.
	if dir := checkedOut(main, branch); dir != "" {
		return open(dir, "agent", "claude", "", false)
	}
	dir := filepath.Join(worktreeRoot, filepath.Base(main), "pr-"+number)
	if _, err := git(main, "worktree", "add", "--detach", dir); err != nil {
		return err
	}
	if _, err := runIn(dir, "gh", "pr", "checkout", number); err != nil {
		git(main, "worktree", "remove", "--force", dir)
		return err
	}
	return prepare(main, dir, "agent", "claude", "")
}

// prepare gives a new worktree the main checkout's ignored files, such as
// .env and .byor, and opens its session.
func prepare(main, dir, layout, agent, prompt string) error {
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
	return open(dir, layout, agent, prompt, false)
}

// send takes a session label or a worktree name.
func send(name, text string) error {
	m := mux()
	id, err := find(m, name)
	if err == nil && id == "" {
		var dir string
		if dir, err = resolveWorktree(name); err != nil {
			return err
		}
		id, err = find(m, labelFor(dir))
	}
	if err != nil {
		return err
	}
	if id == "" {
		return fmt.Errorf("no session for %s", name)
	}
	return m.send(id, text)
}

// remove lets git refuse a worktree with uncommitted changes, and closes the
// session last because ws may be running inside it.
func remove(name string, force bool) error {
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
	if del := "-d"; branch != "" {
		if force {
			del = "-D"
		}
		_, branchErr = git(main, "branch", del, branch)
	}
	m := mux()
	if id, _ := find(m, labelFor(dir)); id != "" {
		if err := m.kill(id); err != nil {
			return err
		}
	}
	return branchErr
}

type worktree struct {
	Project string    `json:"project"`
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Branch  string    `json:"branch"`
	Dirty   bool      `json:"dirty"`
	State   string    `json:"state"` // the session's most urgent agent status, "open", or "" with no session
	Updated time.Time `json:"updated"`
}

func printWorktrees(asJSON bool) error {
	wts := worktrees()
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
func worktrees() []worktree {
	gits, _ := filepath.Glob(filepath.Join(worktreeRoot, "*", "*", ".git"))
	states := agentStates()
	wts := make([]worktree, len(gits))
	var wg sync.WaitGroup
	for i, g := range gits {
		dir := filepath.Dir(g)
		wg.Go(func() {
			w := worktree{Project: filepath.Base(filepath.Dir(dir)), Name: filepath.Base(dir), Path: dir, State: states[labelFor(dir)]}
			status, _ := git(dir, "status", "--porcelain=v2", "--branch")
			for line := range strings.SplitSeq(status, "\n") {
				if b, ok := strings.CutPrefix(line, "# branch.head "); ok {
					w.Branch = b
				} else if line != "" && line[0] != '#' {
					w.Dirty = true
				}
			}
			w.Updated = commitTime(dir)
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

func commitTime(dir string) time.Time {
	out, _ := git(dir, "log", "-1", "--format=%cI")
	t, _ := time.Parse(time.RFC3339, out)
	return t
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
