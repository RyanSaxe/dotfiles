package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"workspace/kitty"
	"workspace/markdown"
	"workspace/mux"
	"workspace/popup"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// A task is a `- [ ]` or `- [x]` line in a markdown file under the vault,
// outside a fenced code block, and the lines it wraps onto. ws reads the
// vault each time it lists tasks and writes a note only to add a task or
// tick one.
type task struct {
	Text    string
	Done    bool
	Due     string // YYYY-MM-DD, from 📅 anywhere in the text
	State   string // overdue, today, soon, later or none
	Project string
	Section string
	File    string // relative to the vault
	Line    int    // the line with the box
}

var (
	taskRe    = regexp.MustCompile(`^\s*- \[([ x])\] +(\S.*)$`)
	headingRe = regexp.MustCompile(`^#{1,6}\s+(.*\S)`)
	fenceRe   = regexp.MustCompile("^\\s*(`{3,}|~{3,})")
	dueRe     = regexp.MustCompile(`\s*📅\s*(\d{4}-\d{2}-\d{2})`)
	// A blank line, a list item, a heading, a quote or a table ends a
	// paragraph in Markdown, so it ends a task's text. A numbered item ends
	// it only from 1, as a line that starts with 390. continues a paragraph.
	breakRe = regexp.MustCompile(`^\s*($|([-*+]|1[.)]|#{1,6})(\s|$)|[>|])`)
)

// vaultDir is the vault's folder, which the switch exports as VAULT_DIR on a
// computer whose host file names a vault, and "" on any other.
func vaultDir() string {
	return os.Getenv("VAULT_DIR")
}

// unfenced calls visit with each line outside a fenced code block.
func unfenced(lines []string, visit func(i int, line string)) {
	fence := ""
	for i, line := range lines {
		if m := fenceRe.FindStringSubmatch(line); m != nil {
			switch fence {
			case "":
				fence = m[1][:1]
			case m[1][:1]:
				fence = ""
			}
		} else if fence == "" {
			visit(i, line)
		}
	}
}

// noteProject names the project of a note in the vault: NAME for a note
// under notes/projects/NAME/ or private/notes/projects/NAME/.
func noteProject(file string) string {
	parts := strings.Split(strings.TrimPrefix(file, "private/"), "/")
	if len(parts) > 3 && parts[0] == "notes" && parts[1] == "projects" {
		return parts[2]
	}
	return ""
}

// noteTasks reads the tasks in one note. file is its path in the vault. A
// wrapped task's lines join with single spaces, and a fence ends its text.
func noteTasks(file, content string, today time.Time) []task {
	var ts []task
	project, section := noteProject(file), ""
	textEnd := -2 // the last line of the last task's text so far
	unfenced(strings.Split(content, "\n"), func(i int, line string) {
		if m := taskRe.FindStringSubmatch(line); m != nil {
			ts = append(ts, task{Text: strings.TrimSpace(m[2]), Done: m[1] == "x", Project: project, Section: section, File: file, Line: i + 1})
			textEnd = i
		} else if i == textEnd+1 && !breakRe.MatchString(line) {
			ts[len(ts)-1].Text += " " + strings.TrimSpace(line)
			textEnd = i
		} else if h := headingRe.FindStringSubmatch(line); h != nil {
			section = h[1]
		}
	})
	for i := range ts {
		applyTaskDue(&ts[i], today)
	}
	return ts
}

func applyTaskDue(t *task, today time.Time) {
	t.State = "none"
	// An impossible date stays part of the text.
	d := dueRe.FindStringSubmatch(t.Text)
	if d == nil || !validDate(d[1]) {
		return
	}
	t.Due, t.Text = d[1], strings.TrimSpace(strings.Replace(t.Text, d[0], "", 1))
	// ISO dates compare as text.
	switch day := today.Format(time.DateOnly); {
	case t.Due < day:
		t.State = "overdue"
	case t.Due == day:
		t.State = "today"
	case t.Due <= today.AddDate(0, 0, 7).Format(time.DateOnly):
		t.State = "soon"
	default:
		t.State = "later"
	}
}

func validDate(s string) bool {
	_, err := time.Parse(time.DateOnly, s)
	return err == nil
}

// vaultTasks reads every task in the vault, skipping hidden folders.
func vaultTasks(vault string, today time.Time) ([]task, error) {
	ts := []task{}
	err := filepath.WalkDir(vault, func(path string, d os.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case strings.HasPrefix(d.Name(), ".") && path != vault:
			if d.IsDir() {
				return filepath.SkipDir
			}
		case !d.IsDir() && strings.HasSuffix(path, ".md"):
			data, err := os.ReadFile(path) //nolint:gosec // reads markdown notes from user's local Obsidian vault
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(vault, path)
			ts = append(ts, noteTasks(filepath.ToSlash(rel), string(data), today)...)
		}
		return nil
	})
	return ts, err
}

// dueDate reads a due date as a person types it: today, tmr, 3d, a weekday
// such as fri, or an ISO date. A weekday named on that weekday means today,
// and blank means no date.
func dueDate(s string, today time.Time) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" || validDate(s) {
		return s, nil
	}
	n, err := dueDateOffset(s, today)
	if err != nil {
		return "", err
	}
	return today.AddDate(0, 0, n).Format(time.DateOnly), nil
}

func dueDateOffset(s string, today time.Time) (int, error) {
	switch s {
	case "today":
		return 0, nil
	case "tmr", "tomorrow":
		return 1, nil
	}
	if days, ok := strings.CutSuffix(s, "d"); ok {
		if n, err := strconv.Atoi(days); err == nil && n >= 0 {
			return n, nil
		}
	}
	for day := time.Sunday; day <= time.Saturday; day++ {
		if len(s) >= 3 && strings.HasPrefix(strings.ToLower(day.String()), s) {
			return (int(day-today.Weekday()) + 7) % 7, nil
		}
	}
	return 0, fmt.Errorf("%q is not a date, so use today, tmr, 3d, a weekday such as fri, or YYYY-MM-DD", s)
}

func taskInsertIndex(lines []string) int {
	at := len(lines)
	unfenced(lines, func(i int, line string) {
		if at == len(lines) && strings.HasPrefix(line, "##") && headingRe.MatchString(line) {
			at = i
		}
	})
	for at > 0 && strings.TrimSpace(lines[at-1]) == "" {
		at--
	}
	return at
}

// addTask appends a task to notes/projects/PROJECT/TODO.md, above the first
// ## heading so it sits with the project's tasks rather than a branch's.
func addTask(vault, project, text, due string) error {
	if project == "" {
		return errors.New("this folder has no origin remote to name the task's project")
	}
	file := filepath.Join(vault, "notes", "projects", project, "TODO.md")
	data, err := os.ReadFile(file) //nolint:gosec // reads project TODO.md inside local vault
	if errors.Is(err, os.ErrNotExist) {
		data, err = []byte("# "+project+"\n"), os.MkdirAll(filepath.Dir(file), 0o750)
	}
	if err != nil {
		return err
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	at := taskInsertIndex(lines)
	entry := []string{"- [ ] " + text}
	if due != "" {
		entry[0] += " 📅 " + due
	}
	if at > 0 && headingRe.MatchString(lines[at-1]) {
		entry = []string{"", entry[0]}
	}
	return os.WriteFile(file, []byte(strings.Join(slices.Insert(lines, at, entry...), "\n")+"\n"), 0o600) //nolint:gosec // writes project TODO.md inside local vault
}

// tickTask turns t's box from [ ] to [x] and leaves every other byte of the
// note as it was. It refuses when the line is no longer that open task,
// since the note may have changed after the list loaded.
func tickTask(vault string, t task, today time.Time) error {
	file := filepath.Join(vault, t.File)
	data, err := os.ReadFile(file) //nolint:gosec // reads local vault markdown note
	if err != nil {
		return err
	}
	now := noteTasks(t.File, string(data), today)
	if i := slices.IndexFunc(now, func(c task) bool { return c.Line == t.Line }); i < 0 || now[i].Text != t.Text || now[i].Done {
		return fmt.Errorf("%s:%d changed since the list loaded, so press ^r to refresh", t.File, t.Line)
	}
	lines := strings.SplitAfter(string(data), "\n")
	lines[t.Line-1] = strings.Replace(lines[t.Line-1], "[ ]", "[x]", 1)
	return os.WriteFile(file, []byte(strings.Join(lines, "")), 0o600) //nolint:gosec // writes local vault markdown note
}

// projectOf names the project a folder's tasks are filed under: the name of
// its origin remote's repository, or "" for a folder without one.
func projectOf(dir string) string {
	url, err := git(dir, "remote", "get-url", "origin")
	if err != nil {
		return ""
	}
	url = strings.TrimSuffix(strings.TrimRight(url, "/"), ".git")
	return url[strings.LastIndexAny(url, "/:")+1:]
}

// taskFolder is the folder whose place a task's note opens in: the checkout
// of the task's project under the home folder, the one with the latest git
// activity when several are, and the vault for a task outside a project or
// one whose project has no checkout on this computer.
func taskFolder(vault string, t task) string {
	dir, latest := vault, time.Time{}
	if t.Project == "" {
		return dir
	}
	for _, repo := range repos() {
		if at := activity(repo); projectOf(repo) == t.Project && (dir == vault || at.After(latest)) {
			dir, latest = repo, at
		}
	}
	return dir
}

// taskTabs are the Inbox's last tabs, which list the vault's open tasks,
// soonest due first: Project tasks and All tasks inside a project, and one
// Tasks tab outside one.
func taskTabs(b mux.Backend, term kitty.Terminal) popup.Popup {
	vault := vaultDir()
	// Without a vault there are no tasks to list, and no note to add one to.
	if vault == "" {
		err := errors.New("the vault isn't set up, since VAULT_DIR is unset")
		return popup.Popup{Noun: "tasks", Tabs: []popup.Tab{{Name: "Tasks"}}, Load: func(int, func([]popup.Row)) ([]popup.Row, error) { return nil, err }}
	}
	project := projectOf(".")
	tabs := []popup.Tab{{Name: "Tasks", Empty: "No open tasks."}}
	if project != "" {
		// The tab isn't named after the project, since a long name would
		// crowd the Inbox's other tabs.
		tabs = []popup.Tab{{Name: "Project tasks", Empty: "No open tasks in " + project + "."}, {Name: "All tasks", Empty: "No open tasks."}}
	}
	return popup.Popup{
		Noun:    "tasks",
		Tabs:    tabs,
		Load:    func(tab int, _ func([]popup.Row)) ([]popup.Row, error) { return loadTaskRows(vault, project, tab) },
		Fetch:   func(r popup.Row) (any, error) { return fetchTaskDoc(vault, r, term) },
		Body:    func(_ popup.Row, d any, w int) string { return d.(markdown.Doc).Render(w, markdownIn("", term)) },
		Actions: taskActions(b, vault, project),
	}
}

func loadTaskRows(vault, project string, tab int) ([]popup.Row, error) {
	tags := map[string]lipgloss.Style{"overdue": popup.Red.SetString("overdue"), "today": popup.Yellow.SetString("today"), "soon": popup.Accent.SetString("soon")}
	ts, err := vaultTasks(vault, time.Now())
	ts = slices.DeleteFunc(ts, func(t task) bool { return t.Done || project != "" && tab == 0 && t.Project != project })
	// ISO dates sort as text, and undated tasks go last.
	slices.SortStableFunc(ts, func(a, b task) int { return strings.Compare(cmp.Or(a.Due, "~"), cmp.Or(b.Due, "~")) })
	rows := make([]popup.Row, len(ts))
	for i, t := range ts {
		id := t.File + ":" + strconv.Itoa(t.Line)
		rows[i] = popup.Row{ID: id, Title: t.Text, Detail: formatTaskNote(id, project, project != "" && tab == 0), Tag: tags[t.State], Data: t}
		if due, parseErr := time.Parse(time.DateOnly, t.Due); parseErr == nil {
			rows[i].Qualifier = due.Format("Jan 2")
		}
	}
	return rows, err
}

// formatTaskNote turns notes/projects/NAME/TODO.md:4 into NAME/TODO.md:4, or
// TODO.md:4 on Project tasks, keeping any private/ prefix.
func formatTaskNote(id, project string, projectTab bool) string {
	note, private := strings.CutPrefix(id, "private/")
	note = strings.TrimPrefix(note, "notes/projects/")
	if projectTab {
		note = strings.TrimPrefix(note, project+"/")
	}
	if private {
		return "private/" + note
	}
	return note
}

func fetchTaskDoc(vault string, r popup.Row, term kitty.Terminal) (any, error) {
	t := r.Data.(task)
	file := filepath.Join(vault, t.File)
	data, err := os.ReadFile(file) //nolint:gosec // reads local vault markdown note for task preview
	lines := strings.Split(string(data), "\n")
	if err != nil || t.Line > len(lines) {
		return nil, err
	}
	return markdown.Load(strings.Join(lines[max(0, t.Line-6):min(len(lines), t.Line+15)], "\n"), markdownIn(filepath.Dir(file), term)), nil
}

func taskActions(b mux.Backend, vault, project string) []popup.Action {
	return []popup.Action{
		{Key: "enter", Help: "edit", Run: func(r popup.Row) tea.Cmd {
			t := r.Data.(task)
			edit := []string{"nvim", "+" + strconv.Itoa(t.Line), filepath.Join(vault, t.File)}
			// Outside Rex and tmux there's no tab to open, so Neovim runs
			// in the popup.
			if !b.Inside() {
				cmd := exec.Command("nvim", "+"+strconv.Itoa(t.Line), filepath.Join(vault, t.File)) //nolint:gosec // opens vault note in local nvim
				return tea.ExecProcess(cmd, func(err error) tea.Msg {
					if err != nil {
						return popup.Notice(err.Error())
					}
					return popup.Reload("")
				})
			}
			return popup.Do(func() error { return runInTab(b, taskFolder(vault, t), edit) }, popup.Quit)
		}},
		{Key: "ctrl+t", Help: "add", Always: true, Run: func(popup.Row) tea.Cmd {
			return askAddTask(vault, project)
		}},
		{Key: "ctrl+x", Help: "done", Run: func(r popup.Row) tea.Cmd {
			t := r.Data.(task)
			return popup.Do(func() error { return tickTask(vault, t, time.Now()) }, popup.Reload("done: "+t.Text))
		}},
	}
}

func askAddTask(vault, project string) tea.Cmd {
	return popup.Ask("task:", func(text string) tea.Cmd {
		if text == "" {
			return nil
		}
		return popup.Ask("due, such as fri or 3d (blank for none):", func(due string) tea.Cmd {
			return popup.Do(func() error {
				date, err := dueDate(due, time.Now())
				if err != nil {
					return err
				}
				return addTask(vault, project, text, date)
			}, popup.Reload("added: "+text))
		})
	})
}
