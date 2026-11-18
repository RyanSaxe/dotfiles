package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"workspace/mux"
)

// A command is one of ws's commands: its line in ws --help, the arguments
// and flags it takes, what ws COMMAND --help says about it, and what it
// runs. A summary, about or flag help breaks its lines with \n.
type command struct {
	name, group   string
	line, summary string // its line in ws --help
	args          string // its arguments, a word each, as its usage names them
	flags         []option
	about, more   string // what ws COMMAND --help says before its flags, and after them
	examples      []string
	run           func(b mux.Backend, c call) error
}

// An option is a flag a command takes, with the word its value is, or no
// word for a switch. The option with no name is --, and the words after it
// are the agent's own.
type option struct{ name, value, help string }

// A call is what one run of a command was given: its arguments, its flags'
// values by name, a switch's value being "true", and the agent's own words.
type call struct {
	args, agentWords []string
	flags            map[string]string
}

// start is how the place a call asks for begins.
func (c call) start() (start, error) {
	s := start{layout: c.flags["layout"], agent: c.flags["agent"], prompt: c.flags["prompt"], flags: c.agentWords}
	switch tab, session := c.flags["tab"] == "true", c.flags["session"] == "true"; {
	case tab && session:
		return s, errors.New("--tab and --session ask for opposite places, so give one of them")
	case tab:
		s.openAs = "tab"
	case session:
		s.openAs = "session"
	}
	return s, nil
}

var (
	agentOption      = option{"agent", "claude|codex", "start this agent instead of the default"}
	promptOption     = option{"prompt", "TEXT", "the agent's first prompt"}
	tabOption        = option{"tab", "", "open the worktree as a tab of its project's session, overriding the\nconfig's open_as"}
	sessionOption    = option{"session", "", "open the worktree as a session of its own, overriding the config's\nopen_as"}
	agentWordsOption = option{"", "FLAGS", "pass FLAGS, such as --model or --effort, to the agent, overriding its\nown settings"}
)

// placesHelp is what ws open, ws new and ws pr --help say about places.
const placesHelp = `
A folder's terminals are in its place: a session labeled after the folder or, for a worktree,
a tab named PROJECT/NAME in any session. A worktree opens as a tab in its project's session,
which ws starts with a plain shell in the main checkout when there is none, or as a session
of its own. open_as in ~/.config/ws/config.toml chooses, and --tab and --session override it.
Any other folder opens as a session.
`

var commands = []command{
	{
		name: "open", group: "Projects and worktrees",
		line: "ws open DIR", summary: "switch to the folder's tab or session, or open one",
		args:  "DIR",
		flags: []option{{"layout", "NAME", "the layout a new place opens with, agent by default"}, tabOption, sessionOption},
		about: `Switch to folder DIR's place, its tab or session, or open one for it when it has none.
Outside Rex and tmux there is no terminal to open one in, so ws open fails.`,
		more: placesHelp + `
A layout is the panes a new place opens with, in ~/.config/ws/layouts/NAME.toml. agent,
review and file are built in: agent runs the agent beside a shell, review opens {pr} in
Neovim, and file opens {file} in Neovim. A pane's run can use {agent}, {prompt}, {pr}, {file},
{dir} and {name}.
`,
		examples: []string{"ws open ~/generic/dotfiles", "ws open . --layout file", "ws open ~/worktrees/dotfiles/fix-login --session"},
		run: func(b mux.Backend, c call) error {
			dir, _ := filepath.Abs(c.args[0])
			if info, err := os.Stat(dir); err != nil || !info.IsDir() {
				return fmt.Errorf("%s is not a folder", dir)
			}
			s, err := c.start()
			if err != nil {
				return err
			}
			return open(b, dir, s, true)
		},
	},
	{
		name: "tab", group: "Projects and worktrees",
		line: "ws tab DIR -- COMMAND", summary: "run a command in a new tab of the folder's tab or session",
		args:  "DIR",
		flags: []option{{"", "COMMAND", "the command to run, with its arguments, word for word"}},
		about: `Run COMMAND in a new tab of folder DIR's place, its tab or session. The tab closes when
COMMAND exits. When DIR has no place, ws opens one as ws open does, a worktree as a tab or a
session as open_as in ~/.config/ws/config.toml says, and types COMMAND into its shell in
place of a layout. Run by a person, ws tab goes to the new tab, and run by an agent, it
leaves the view alone. pair's launch script opens each agent it spawns this way. Outside Rex
and tmux there is no terminal to open a tab in, so ws tab fails.`,
		examples: []string{"ws tab . -- htop", "ws tab ~/worktrees/dotfiles/fix-login -- claude --effort high"},
		run: func(b mux.Backend, c call) error {
			dir, _ := filepath.Abs(c.args[0])
			if info, err := os.Stat(dir); err != nil || !info.IsDir() {
				return fmt.Errorf("%s is not a folder", dir)
			}
			command := c.agentWords // the words after --
			if len(command) == 0 {
				return errors.New("it needs the command to run after --, such as ws tab . -- htop")
			}
			return runInTab(b, dir, command)
		},
	},
	{
		name: "new", group: "Projects and worktrees",
		line: "ws new NAME", summary: "make a worktree on a new branch and start an agent in it",
		args: "NAME",
		flags: []option{
			agentOption, promptOption,
			{"layout", "NAME", "the layout to open, agent by default"},
			{"base", "REF", "start the branch from REF instead of HEAD"},
			tabOption, sessionOption,
			agentWordsOption,
		},
		about: `Make a worktree in ~/worktrees/PROJECT/NAME on a new branch NAME, copy the main checkout's
ignored files, such as .env, into it, and start an agent there. It refuses when a tab or
session named PROJECT/NAME is already open. Outside Rex and tmux, it only makes the worktree
and prints its path.`,
		more: placesHelp,
		examples: []string{
			"ws new fix-login",
			`ws new fix-login --agent codex --prompt "Fix the redirect" --base main`,
			"ws new fix-popups -- --effort high --model opus",
			"ws new fix-popups --session",
		},
		run: func(b mux.Backend, c call) error {
			s, err := c.start()
			if err != nil {
				return err
			}
			return newWorktree(b, ".", c.args[0], c.flags["base"], s)
		},
	},
	{
		name: "pr", group: "Projects and worktrees",
		line: "ws pr NUMBER", summary: "check out a pull request in a worktree and open it",
		args: "NUMBER",
		flags: []option{
			agentOption, promptOption,
			{"layout", "NAME", "the layout to open, agent by default. review opens the pull request\nin Neovim instead"},
			tabOption, sessionOption,
			agentWordsOption,
		},
		about: `Check out pull request NUMBER of this project in ~/worktrees/PROJECT/pr-NUMBER, or open the
checkout that already has its branch, and start an agent there.`,
		more: placesHelp,
		examples: []string{
			"ws pr 123",
			`ws pr 123 --prompt "List what should change before this merges"`,
			"ws pr 123 --layout review",
			"ws pr 123 -- --effort high",
		},
		run: func(b mux.Backend, c call) error {
			s, err := c.start()
			if err != nil {
				return err
			}
			_, err = pullRequest(b, ".", c.args[0], s)
			return err
		},
	},
	{
		name: "ls", group: "Projects and worktrees",
		line: "ws ls", summary: "list worktrees and their agents",
		flags: []option{{"json", "", "print them as JSON, with each one's path and last commit"}},
		about: `List the worktrees under ~/worktrees by project, this project's first, with each one's
branch, whether it has uncommitted changes, and the state of the agents in its tab or session.`,
		examples: []string{"ws ls", "ws ls --json | jq -r '.[].path'"},
		run: func(b mux.Backend, c call) error {
			return printWorktrees(b, c.flags["json"] == "true")
		},
	},
	{
		name: "rm", group: "Projects and worktrees",
		line: "ws rm NAME", summary: "remove a worktree, its branch and its tab or session",
		args:  "NAME",
		flags: []option{{"force", "", "remove the worktree and delete its branch anyway"}},
		about: `Remove worktree NAME, delete its branch and close its tab or session, which leaves the rest
of its project's session open. NAME is the worktree's folder under ~/worktrees/PROJECT, or
PROJECT/NAME when several projects have one. ws rm refuses a worktree with uncommitted
changes, and keeps a branch that git doesn't call merged unless GitHub shows its pull
request merged.`,
		examples: []string{"ws rm fix-login", "ws rm dotfiles/fix-login --force"},
		run: func(b mux.Backend, c call) error {
			return remove(b, c.args[0], c.flags["force"] == "true")
		},
	},
	{
		name: "pick", group: "Popups",
		line: "ws pick NAME", summary: "open a popup: go, sessions, worktrees, agents, reviews,\ntasks, theme, keys or files",
		args:  "NAME",
		flags: []option{{"client", "ID", "the Rex app a picked row switches, which Rex's keys pass. Without it,\nws switches the app that shows this terminal"}},
		about: `Open popup NAME: go, sessions, worktrees, agents, reviews, tasks, theme, keys or files.
sessions is the go popup on its Sessions tab. go also lists the folders in
~/.config/ws/bookmarks, one per line.`,
		more: `
In every popup:
  typing                   filter the rows
  ↑ ↓, Ctrl-J/K, Ctrl-N/P  move, as the mouse wheel does
  Enter                    go to or open the row, as a click does
  Tab, Shift-Tab           switch tabs
  Ctrl-D, Ctrl-U           scroll the details half a page
  Ctrl-R                   load the rows again
  Esc                      clear the filter, or close the popup
  Ctrl-C                   close the popup

When the popup is under 80 columns wide, → shows the row's details, and ← or Esc goes back to
the rows.

A popup's own keys mean the same in every popup that has them, and the bottom line lists only
the ones that work on the selected row:
  Ctrl-T                   start something new
  Ctrl-X                   finish or remove the row
  Ctrl-F                   search the row's folder
  Ctrl-G                   show a diff
  Ctrl-O                   open the browser
`,
		examples: []string{"ws pick go", "ws pick theme"},
		run: func(b mux.Backend, c call) error {
			return pick(b, c.args[0])
		},
	},
	{
		name: "focus", group: "Popups",
		line: "ws focus agent|tasks|reviews", summary: "bring Rex forward, then jump to the agent that needs you\nor open Tasks or Reviews. Cmd-Alt-A, T and R run it",
		args: "agent|tasks|reviews",
		about: `Bring Rex onto AeroSpace's code workspace, or Ghostty on tmux when Rex isn't installed.
Then ws focus agent goes to the agent that needs you first, and to the next one each time it
runs, or to each agent in turn when none needs you. tasks and reviews open Tasks or Reviews.
AeroSpace's Cmd-Alt-A, T and R run it.`,
		examples: []string{"ws focus agent", "ws focus reviews"},
		run: func(b mux.Backend, c call) error {
			return focus(c.args[0])
		},
	},
	{
		name: "agent", group: "Settings",
		line: "ws agent", summary: "print the agent ws starts, with its model and effort",
		about: `Print the agent ws starts, which ~/.config/ws/config.toml names, then the model and effort
its own settings give it: model and effortLevel in ~/.claude/settings.json for claude, and
model and model_reasoning_effort in ~/.codex/config.toml for codex. home-switch writes the
config from the host file's dotfiles.ws.agent, and the agents' settings from
modules/home/agents.nix, so every session of the agent shares them. ws starts the agent with
no flags of its own, and ws new and ws pr pass it the words after their --, which override
its settings for that session.`,
		examples: []string{"ws agent", "ws new fix-login -- --effort high"},
		run: func(b mux.Backend, c call) error {
			return printAgent()
		},
	},
	{
		name: "mascot", group: "Settings",
		line: "ws mascot NAME", summary: "set the popups' mascot: a Pokémon, shiny-pokemon:NAME\nor a PNG file",
		args: "NAME",
		about: `Set the popups' mascot, which also gives them their accent color. NAME is a Pokémon, such as
pikachu, shiny-pokemon:NAME for its shiny form, or a PNG file. The theme popup sets it too.`,
		examples: []string{"ws mascot pikachu", "ws mascot shiny-pokemon:gengar", "ws mascot ~/Pictures/cat.png"},
		run: func(b mux.Backend, c call) error {
			return setMascot(c.args[0])
		},
	},
	{
		name: "attention", group: "Background",
		line: "ws attention [--watch]", summary: "print what needs you, or keep sketchybar's A, R and T\ncurrent",
		flags: []option{{"watch", "", "keep sketchybar's A, R and T current instead, and fetch the inbox\nReviews lists every 5 minutes. A launchd agent runs it on each Mac"}},
		about: `Print what needs you, as three words: agents (failed, waiting, done or none), reviews (ci,
review or none) and tasks (overdue, today, tomorrow or none).`,
		examples: []string{"ws attention", "ws attention --watch"},
		run: func(b mux.Backend, c call) error {
			return attention(b, c.flags["watch"] == "true")
		},
	},
}

// usage is what ws --help prints: each group of commands, a line each.
func usage() string {
	var b strings.Builder
	b.WriteString("usage: ws COMMAND [ARGS], and ws COMMAND --help for its flags and examples\n")
	for i, c := range commands {
		if i == 0 || c.group != commands[i-1].group {
			fmt.Fprintf(&b, "\n%s\n", c.group)
		}
		fmt.Fprintf(&b, "  %-30s%s\n", c.line, indent(c.summary, 32))
	}
	return b.String()
}

// help is what ws COMMAND --help prints.
func (c command) help() string {
	var b strings.Builder
	fmt.Fprintf(&b, "usage: %s\n\n%s\n", c.usage(), c.about)
	width := 0
	for _, o := range c.flags {
		width = max(width, len(o.words()))
	}
	if len(c.flags) > 0 {
		b.WriteString("\n")
	}
	for _, o := range c.flags {
		fmt.Fprintf(&b, "  %-*s  %s\n", width, o.words(), indent(o.help, width+4))
	}
	b.WriteString(c.more)
	b.WriteString("\nExamples:\n")
	for _, e := range c.examples {
		fmt.Fprintf(&b, "  %s\n", e)
	}
	return b.String()
}

// usage is the command with its arguments and every flag.
func (c command) usage() string {
	words := []string{"ws", c.name}
	if c.args != "" {
		words = append(words, c.args)
	}
	for _, o := range c.flags {
		words = append(words, "["+o.words()+"]")
	}
	return strings.Join(words, " ")
}

// words is the option as typed, with its value's word.
func (o option) words() string {
	return strings.TrimSpace("--" + o.name + " " + o.value)
}

func indent(text string, width int) string {
	return strings.ReplaceAll(text, "\n", "\n"+strings.Repeat(" ", width))
}

// run runs ws COMMAND with the words after it, in the multiplexer backend
// gives for the Rex app named by --client, and its errors start with the
// command.
func run(name string, words []string, backend func(client string) mux.Backend) error {
	i := slices.IndexFunc(commands, func(c command) bool { return c.name == name })
	if i < 0 {
		return fmt.Errorf("ws: %s isn't a command, see ws --help", name)
	}
	c := commands[i]
	// The agent's words are its own, so --help among them is the agent's.
	own := words
	if j := slices.Index(words, "--"); j >= 0 {
		own = words[:j]
	}
	if slices.ContainsFunc(own, func(w string) bool { return slices.Contains([]string{"-h", "-help", "--help"}, w) }) {
		fmt.Print(c.help())
		return nil
	}
	in, err := c.parse(words)
	if err == nil {
		err = c.run(backend(in.flags["client"]), in)
	}
	if err != nil {
		return fmt.Errorf("ws %s: %w", c.name, err)
	}
	return nil
}

// parse reads a command's words. Flags may come before or after its
// arguments, and each flag's value follows it or an =.
func (c command) parse(words []string) (call, error) {
	in := call{flags: map[string]string{}}
words:
	for i := 0; i < len(words); i++ {
		w := words[i]
		if !strings.HasPrefix(w, "-") || w == "-" {
			in.args = append(in.args, w)
			continue
		}
		flag, value, hasValue := strings.Cut(w, "=")
		name := strings.TrimLeft(flag, "-")
		j := slices.IndexFunc(c.flags, func(o option) bool { return o.name == name })
		switch {
		case j < 0:
			return in, fmt.Errorf("%s isn't a flag of ws %s, which takes %s", flag, c.name, c.flagNames())
		case name == "":
			in.agentWords = words[i+1:]
			break words
		case c.flags[j].value == "" && hasValue:
			return in, fmt.Errorf("%s takes no value", flag)
		case c.flags[j].value == "":
			in.flags[name] = "true"
		case !hasValue && i+1 == len(words):
			return in, fmt.Errorf("%s needs %s after it", flag, c.flags[j].value)
		case !hasValue:
			i++
			in.flags[name] = words[i]
		default:
			in.flags[name] = value
		}
	}
	if want := len(strings.Fields(c.args)); len(in.args) != want {
		return in, fmt.Errorf("it takes %s, see ws %s --help", cmp.Or(c.args, "no arguments"), c.name)
	}
	return in, nil
}

// flagNames lists the command's flags, but not its --.
func (c command) flagNames() string {
	var names []string
	for _, o := range c.flags {
		if o.name != "" {
			names = append(names, "--"+o.name)
		}
	}
	switch len(names) {
	case 0:
		return "no flags"
	case 1:
		return names[0]
	}
	return strings.Join(names[:len(names)-1], ", ") + " and " + names[len(names)-1]
}
